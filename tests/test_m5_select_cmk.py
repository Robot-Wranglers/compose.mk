"""Unit contract for `m5.select` / `m5.pluck` (compose.mk).

Both take a list and a `%` pattern naming a variable to probe: `%` is
substituted with each element, and the element is kept iff that variable is
defined. `m5.select` returns the elements, `m5.pluck` their values. The
pattern says which half varies, so one helper serves both a fixed attribute
over varying objects and varying attributes under a fixed prefix.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")

# b has no .x; e.x is defined but empty; m.x is multi-word.
_VARS = ["a.x = 1", "c.x = 3", "b.y = 9", "e.x =", "m.x = one two",
         "p.a = A", "p.c = C"]

# key, expression, expected -- each becomes one echo line and one assertion.
_CASES = [
  ("sel", "$(call m5.select, a b c, %.x)", "a c"),
  ("plk", "$(call m5.pluck, a b c, %.x)", "1 3"),
  ("selPre", "$(call m5.select, a b c, p.%)", "a c"),
  ("plkPre", "$(call m5.pluck, a b c, p.%)", "A C"),
  ("selEmptyList", "$(call m5.select, , %.x)", ""),
  ("plkEmptyList", "$(call m5.pluck, , %.x)", ""),
  ("selNoHits", "$(call m5.select, q r, %.x)", ""),
  ("selEmptyVal", "$(call m5.select, a e c, %.x)", "a e c"),
  ("plkEmptyVal", "$(call m5.pluck, a e c, %.x)", "1 3"),
  ("plkMulti", "$(call m5.pluck, a m, %.x)", "1 one two"),
  ("selOrder", "$(call m5.select, c a, %.x)", "c a"),
  ("selUnpadded", "$(call m5.select,a b c,%.x)", "a c"),
]

_BODY = "\n".join(
  _VARS + ["", "__main__:"]
  + [f'\t@echo "{key}=[{expr}]"' for key, expr, _ in _CASES]
) + "\n"


@pytest.fixture(scope="module")
def out(tmp_path_factory):
  f = tmp_path_factory.mktemp("m5select") / "t.cmk"
  f.write_text(_BODY)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  text = _ANSI.sub("", r.stdout + r.stderr)
  assert r.returncode == 0, text
  return text


def _line(out, key):
  return next(ln for ln in out.splitlines() if ln.startswith(f"{key}="))


@pytest.mark.parametrize("key,expr,expected", _CASES, ids=[c[0] for c in _CASES])
def test_case(out, key, expr, expected):
  assert _line(out, key) == f"{key}=[{expected}]", out


@pytest.mark.parametrize("key", ["sel", "selPre", "selUnpadded"])
def test_result_is_whitespace_normalized(out, key):
  # a skipped element must leave no gap, since callers comma-join the result.
  assert "  " not in _line(out, key), _line(out, key)
