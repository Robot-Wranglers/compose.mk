"""Phase-1 probe: `isinstance`/`issubclass` hosted inside a real
`cmk.module __builtins__(| .. |)` declaration in the `__sandbox__` partition.

The construct lowers a `module NAME(| body |)` to a `define NAME .. endef`
(raw body) plus `$(call cmk.module, def=NAME)`; the namespace ctor hoists each
body head QUALIFIED under `NAME.` (so `isinstance = ..` -> `__builtins__.isinstance
= ..`), ONE define per member -- no forwarder, no `cmk.X = $(call ..)` twin.

All probes activate the sandbox via `CMK_SANDBOX=1` in the child env.  Docker-free;
models `tests/test_self_cmk.py`'s `_run_cmk` helper.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.module_system]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_SANDBOX_ENV = {**os.environ, "CMK_SANDBOX": "1"}


def _run_cmk(body, tmp_path, *targets, timeout=200):
  f = tmp_path / "builtinsmod.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout, env=_SANDBOX_ENV,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


# ---- prove-1: the module hosts the members, qualified, single-def -----------
def test_qualified_members_compute_is_a(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| |)\n"
    "widget w(| |)\n"
    "__main__:\n"
    "\t@printf 'B_ISA=[%s] B_SUB=[%s] B_NEG=[%s]\\n' "
    "\"$(call __builtins__.isinstance,w,widget)\" "
    "\"$(call __builtins__.issubclass,widget,widget)\" "
    "\"$(call __builtins__.isinstance,w,nope)\"\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "B_ISA=[1] B_SUB=[1] B_NEG=[]" in out, out


# ---- prove-2: the hoisted head is qualified + self-ref-qualified, no fwd ----
def test_hoisted_output_is_qualified_single_def(tmp_path):
  r, out = _run_cmk(
    "__main__:\n"
    "\t@printf 'ISA=%s\\n' '$(value __builtins__.isinstance)'\n"
    "\t@printf 'SUB=%s\\n' '$(value __builtins__.issubclass)'\n"
    "\t@printf 'ALL=%s\\n' '$(__builtins__.__all__)'\n",
    tmp_path)
  assert r.returncode == 0, out
  # the isinstance member calls its SIBLING by the QUALIFIED name (proof the
  # hoister rewrote the self-call, and that it is a real macro not a forwarder).
  assert "ISA=$(call __builtins__.issubclass," in out, out
  assert "$(strip ${1}).__mro__" in out, out          # issubclass body verbatim
  assert "SUB=$(if $(filter $(strip ${2})," in out, out
  assert "ALL=isinstance issubclass" in out, out       # __all__ fully-qualified


# ---- prove-3a: bindable bare after lang.module.bind -------------------------
def test_bind_bare(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| |)\n"
    "widget w(| |)\n"
    "$(call lang.module.bind,__builtins__,$(__builtins__.__all__))\n"
    "__main__:\n"
    "\t@printf 'BOUND_ISA=[%s] BOUND_SUB=[%s]\\n' "
    "\"$(call isinstance,w,widget)\" "
    "\"$(call issubclass,widget,widget)\"\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "BOUND_ISA=[1] BOUND_SUB=[1]" in out, out


# ---- prove-3b: floor precedence -- a user redefine wins over the binding ----
def test_bind_is_floor(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| |)\n"
    "widget w(| |)\n"
    "$(call lang.module.bind,__builtins__,$(__builtins__.__all__))\n"
    "isinstance = USERWINS\n"
    "__main__:\n"
    "\t@printf 'FLOOR=[%s]\\n' \"$(call isinstance,w,widget)\"\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "FLOOR=[USERWINS]" in out, out


# ---- prove-4: the sandbox partition still compiles with the addition --------
def test_sandbox_partition_still_compiles():
  r = subprocess.run(
    [str(COMPOSE), "sandbox.selftest"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=200, env=_SANDBOX_ENV,
  )
  out = _ANSI.sub("", r.stdout + r.stderr)
  assert r.returncode == 0, out
  assert "sandbox partition is live" in out, out
  assert re.search(r"(^|\n)ok(\n|$)", out), out
