"""Multi-line recipe-level capture: LHS <- (| .. |) / LHS <- [| .. |] whose
matching close is on a LATER line (the `.awk.lambdalift` multi-line arm).

Three outcomes, mirrored here:
  RAW (| .. |)      -> `define __cap_N` run from a tmpfile (`bash` + a
                       `_mk.def.tmpfile`), so many body lines are fine.
  COOKED [| triple-quote body |] -> cooks to ONE `printf` line, so the inline
                       `$(__cap_N)` stays single-line + recipe-scoped (cooked lift).
  COOKED, any other multi-line body -> compile `$(error ..)` (would split the recipe).

Promoted from a throwaway `demo.capture` in demos/cmk/banana-recipes.cmk.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.compiler, pytest.mark.covers_demo("banana-recipes.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, src):
  f = tmp_path / "cap.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return p


# --- compile-level lowering --------------------------------------------------


def test_multiline_raw_capture_lifts_to_define(ir):
  out = ir("demo:\n\tx <- (|\n\t  echo one\n\t  echo two\n\t|)\n\techo done\n")
  assert "define __cap_" in out
  assert "echo one" in out and "echo two" in out
  assert "bash $(call _mk.def.tmpfile, __cap_" in out


def test_multiline_cooked_triplequote_lifts_cooked(ir):
  out = ir('demo:\n\tx <- [|\n\t  """a\n\t  b"""\n\t|]\n')
  # the triple-quote collapses to one printf line, lifted as cooked + inlined
  assert "=`$(__cap_" in out
  assert "printf" in out


def test_multiline_cooked_nontriplequote_is_error(ir):
  out = ir("demo:\n\tx <- [|\n\t  echo one\n\t  echo two\n\t|]\n")
  assert "$(error" in out and "multi-line cooked capture" in out


def test_singleline_capture_unchanged(ir):
  # the pre-existing single-line arm still lowers as before.
  out = ir("demo:\n\tx <- [| echo hi |]\n\techo \"$$x\"\n")
  assert "=`$(__cap_" in out


# --- end-to-end run ----------------------------------------------------------


def test_multiline_raw_capture_runs(tmp_path):
  src = 'demo:\n\tx <- (|\n\t  echo one\n\t  echo two\n\t|)\n\tprintf "got:%s\\n" "$$x"\n__main__: demo\n'
  p = _run(tmp_path, src)
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "one" in p.stdout and "two" in p.stdout


def test_multiline_cooked_triplequote_runs(tmp_path):
  src = 'demo:\n\tx <- [|\n\t  """alpha\n\t  beta"""\n\t|]\n\tprintf "%s\\n" "$$x"\n__main__: demo\n'
  p = _run(tmp_path, src)
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "alpha" in p.stdout and "beta" in p.stdout


# --- anonymous-immediate `ctor(| body |).method(args)` -----------------------

# A toy constructor: copy the body aside (before it is redefined) + a `.say`
# method that echoes it -- the same copy-first shape jqlang uses.
_CTOR = (
  "define _wrap.def\n"
  "$(1).body := $$(value $(1))\n"
  "$(1).say = echo said:$$($(1).body)\n"
  "endef\n"
  "$(call m5.def.!, _wrap, _wrap.def)\n"
  "wrap = $(call _wrap, $(call mk.kwargs.get,${1},def))\n"
)


def test_anon_immediate_lifts_and_hoists(ir):
  # `ctor(| body |).method()` on one recipe line -> gensym define + hoisted
  # `$(call ctor, def=__lambda_N)` + inline `$(call __lambda_N.method)`.
  out = ir(_CTOR + "demo:\n\twrap(| payload |).say()\n")
  assert "define __lambda_" in out and "payload" in out
  assert "$(call wrap, def=__lambda_" in out
  assert "$(call __lambda_" in out and ".say)" in out


def test_anon_immediate_runs(cmk, tmp_path):
  src = _CTOR + "demo:\n\twrap(| payload |).say()\n__main__: demo\n"
  p = _run(tmp_path, src)
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "said:payload" in p.stdout
