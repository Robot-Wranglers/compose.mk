"""Recipe-level captures must be INDENTATION-INVARIANT: a `LHS <- (| .. |)` /
`LHS <- [| .. |]` written with the 2-space house style must lower to the SAME
recipe-level shell capture as its tab-indented twin.

Today it does not. The `sugar` stage classifies a capture as module-level vs
recipe-level by a literal-TAB regex (`/^\t.../`), but the `indent` stage that
normalizes 2-space -> tab runs much later in the pipeline. So at sugar time a
2-space recipe capture is indistinguishable from a col-0 module capture and is
misclassified:

  tab      `\tx <- (| .. |)`   -> `x=`bash ..``            (recipe capture)  OK
  2-space  `  x <- (| .. |)`   -> `x := $(shell ..)`       (module assign)   BUG
  2-space  `  x <- [| .. |]`   -> `$(error .. module-level cooked capture)`  BUG

These tests assert the HEALED behavior and are xfail(strict=True) until the
sugar stage is made recipe-context-aware (col-0 = module, ANY indent = recipe).
When the fix lands they xpass -> strict flips the suite red -> remove the marker.
Twins of the tab cases in test_recipe_capture_multiline_cmk.py.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

_HEAL = pytest.mark.xfail(
  reason="sugar stage keys on literal tab; 2-space recipe captures misclassify "
  "as module-level. Heal by making capture detection recipe-context-aware.",
  strict=True,
)


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


# --- compile-level lowering: 2-space twins of the tab cases ------------------


@_HEAL
def test_2space_raw_singleline_is_recipe_capture(ir):
  # tab twin: test_singleline_capture_unchanged -> `x=`bash ..``
  out = ir("demo:\n  x <- (| echo hi |)\n  echo \"$$x\"\n")
  assert "=`bash $(call _mk.def.tmpfile, __cap_" in out
  assert "x := $(shell" not in out  # must NOT lower to a module assignment


@_HEAL
def test_2space_cooked_singleline_is_recipe_capture(ir):
  # tab twin asserts `=`$(__cap_`; 2-space must not raise the module-cooked error
  out = ir("demo:\n  x <- [| echo hi |]\n  echo \"$$x\"\n")
  assert "=`$(__cap_" in out
  assert "module-level cooked capture" not in out


@_HEAL
def test_2space_multiline_raw_capture_lifts_to_define(ir):
  # tab twin: test_multiline_raw_capture_lifts_to_define
  out = ir("demo:\n  x <- (|\n    echo one\n    echo two\n  |)\n  echo done\n")
  assert "define __cap_" in out
  assert "echo one" in out and "echo two" in out
  assert "=`bash $(call _mk.def.tmpfile, __cap_" in out
  assert "x := $(shell" not in out


# --- end-to-end run ----------------------------------------------------------


@_HEAL
def test_2space_raw_capture_runs(tmp_path):
  src = 'demo:\n  x <- (|\n    echo one\n    echo two\n  |)\n  printf "got:%s\\n" "$$x"\n__main__: demo\n'
  p = _run(tmp_path, src)
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "one" in p.stdout and "two" in p.stdout
