"""Unit contract for `m5|`, the read-or-default accessor (compose.mk).

`$(call m5|, name, default)` reads the named variable when it is defined and
yields the default when it is not. Definedness is origin-based, so a variable
assigned the empty string reads back empty instead of falling through. That is
what separates it from `$(or ..)`. The default is an ordinary call argument, so
it expands either way: a costly fallback belongs in a variable, not here.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")

_VARS = ["hit = yes", "empty =", "spaced =   padded   "]

# key, expression, expected -- one echo line and one assertion each.
_CASES = [
  ("hit", "$(call m5|,hit,fallback)", "yes"),
  ("miss", "$(call m5|,nosuchvar,fallback)", "fallback"),
  ("emptyVar", "$(call m5|,empty,fallback)", ""),
  ("emptyDefault", "$(call m5|,nosuchvar,)", ""),
  ("valueNotStripped", "$(call m5|,spaced,fallback)", "padded   "),
  ("nameIsStripped", "$(call m5|, hit , fallback)", "yes"),
]

_BODY = "\n".join(
  _VARS + ["", "__main__:"]
  + [f'\t@echo "{key}=[{expr}]"' for key, expr, _ in _CASES]
) + "\n"


def _run(path):
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(path)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


@pytest.fixture(scope="module")
def out(tmp_path_factory):
  f = tmp_path_factory.mktemp("m5default") / "t.cmk"
  f.write_text(_BODY)
  r, text = _run(f)
  assert r.returncode == 0, text
  return text


@pytest.mark.parametrize("key,expr,expected", _CASES, ids=[c[0] for c in _CASES])
def test_case(out, key, expr, expected):
  line = next(ln for ln in out.splitlines() if ln.startswith(f"{key}="))
  assert line == f"{key}=[{expected}]", out


def test_default_expands_even_on_a_hit(tmp_path):
  # the marker proves the unused branch ran, which is why costly fallbacks stay out.
  marker = tmp_path / "touched"
  f = tmp_path / "t.cmk"
  f.write_text(
    "hit = yes\n"
    f"probe = $(shell touch {marker}; echo D)\n"
    "\n__main__:\n"
    '\t@echo "eagerHit=[$(call m5|,hit,$(probe))]"\n'
  )
  r, text = _run(f)
  assert r.returncode == 0, text
  assert "eagerHit=[yes]" in text, text
  assert marker.exists(), "default was not expanded on a hit"
