"""The `%` template-fill operator -- `(| a |) % (| kwargs |)` (TODO-mod-operator.md).

`%` is a Table-A banana operator (`%=__mod__`): `A % B` -> `A.__mod__(B)` fills A's `@@holes@@` from
B's shape (a kwargs fragment), routed through the same fold as `+`/`|` -- no bespoke arm. Pure STRING
algebra (a pure banana is text; nothing executes without a machine).  The `&`-handle capture binds the
folded fragment as a lazy handle; `$(LHS)` reads its filled text.  Chains left-associative.

Docker-free (make only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, src):
  f = tmp_path / "mod.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=120,
  )
  return r.stdout + r.stderr


def test_single_fill_binds_handle(tmp_path):
  out = _run(tmp_path, 'demo:\n\t&x <- (| hi @@who@@ |) % (| who=bob |)\n\t@echo "x=[$(x)]"\n__main__: demo\n')
  assert "x=[hi bob]" in out, out


def test_chained_fill_left_assoc(tmp_path):
  out = _run(tmp_path, 'demo:\n\t&y <- (| @@a@@-@@b@@ |) % (| a=1 |) % (| b=2 |)\n\t@echo "y=[$(y)]"\n__main__: demo\n')
  assert "y=[1-2]" in out, out


def test_repeated_hole_fills_every_occurrence(tmp_path):
  out = _run(tmp_path, 'demo:\n\t&z <- (| @@w@@:@@w@@ |) % (| w=X |)\n\t@echo "z=[$(z)]"\n__main__: demo\n')
  assert "z=[X:X]" in out, out


def test_semicolon_recipe_form(tmp_path):
  # `tgt:; &x <- ..` (the `;`-recipe form) fires the same as a separate-line capture: bind at parse,
  # the bare `tgt:` survives so the target still exists.
  out = _run(tmp_path, 'semi:; &x <- (| hi @@who@@ |) % (| who=bob |)\ndemo: semi\n\t@echo "x=[$(x)]"\n__main__: demo\n')
  assert "x=[hi bob]" in out, out


def test_pure_string_no_execution(tmp_path):
  # a pure banana is text: `%` fills, it does NOT run.  A body that would be a bad shell command still
  # just yields its filled text (no `command not found`).
  out = _run(tmp_path, 'demo:\n\t&q <- (| notacmd @@x@@ |) % (| x=1 |)\n\t@echo "q=[$(q)]"\n__main__: demo\n')
  assert "q=[notacmd 1]" in out and "command not found" not in out, out
