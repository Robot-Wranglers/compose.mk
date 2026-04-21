"""Always-on probe for the promoted `__builtins__` module.

Proves that bare `$(call isinstance,..)` / `$(call issubclass,..)` resolve in a
NORMAL `cmk run` program with NO CMK_SANDBOX and NO explicit `lang.module.bind`
line -- because core star-imports `__builtins__.__all__` bare at load (the hosted
`cmk.module __builtins__(| .. |)` decl + the load-time bind after the partition
`-include`).  Also pins floor precedence (a user redefine wins) and the
`__builtins__.__all__` manifest.

Docker-free; models `tests/test_self_cmk.py`'s `_run_cmk` helper.  NO sandbox env.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=200):
  f = tmp_path / "builtinspromoted.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


# ---- prove-1: bare isinstance/issubclass, NO sandbox, NO bind line ----------
def test_bare_isinstance_issubclass_always_on(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| |)\n"
    "widget w(| |)\n"
    "__main__:\n"
    "\t@printf 'ISA=[%s] SUB=[%s] NEG=[%s]\\n' "
    "\"$(call isinstance,w,widget)\" "
    "\"$(call issubclass,widget,widget)\" "
    "\"$(call isinstance,w,nope)\"\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "ISA=[1] SUB=[1] NEG=[]" in out, out


# ---- prove-2: floor precedence -- a user redefine shadows the builtin -------
def test_builtin_is_floor_user_redef_wins(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| |)\n"
    "widget w(| |)\n"
    "isinstance = USERWINS\n"
    "__main__:\n"
    "\t@printf 'FLOOR=[%s]\\n' \"$(call isinstance,w,widget)\"\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "FLOOR=[USERWINS]" in out, out


# ---- prove-3: the module manifest is exactly the two predicates -------------
def test_builtins_all_manifest(tmp_path):
  r, out = _run_cmk(
    "__main__:\n"
    "\t@printf 'ALL=[%s]\\n' '$(sort $(__builtins__.__all__))'\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "ALL=[isinstance issubclass]" in out, out


# ---- prove-4: the bare `__builtins__` enumerator target still works ---------
def test_enumerator_reclaim_intact():
  r = subprocess.run(
    [str(COMPOSE), "__builtins__"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  out = _ANSI.sub("", r.stdout)
  assert r.returncode == 0, _ANSI.sub("", r.stdout + r.stderr)
  heads = set(out.split())
  assert "flux.ok" in heads, out
  assert "help" in heads, out
