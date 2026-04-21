"""Class-body bare assignments should bind CLASS attributes, not leak to global.

cmk's data model is Python-style: `class Foo: bar = baz` binds `Foo.bar`.  The cmk
analogue `cmk.class Foo(| bar:=baz |)` should bind `Foo.bar` (a class attribute),
but today a bare (non-`${self}`) assignment in a class body lands in the GLOBAL
namespace -- so `$(Foo.bar)` is empty while `$(bar)` is set.  Confirmed for plain
AND umbrella/nested-name classes, so it is a class-body issue, not umbrella-only.

Real footgun, not cosmetic: two classes that each write `fmtentry:=X` in their body
clobber the SAME global `fmtentry` -- surfaced building dsl.golang/dsl.rust, whose
per-language spec code.compiled reads as `$(<class>.fmtentry)` (compose.mk:5361), so
the class-scoped read finds nothing.  Docker-free.

The first test PINS the current (buggy) leak; the second is xfail(strict) for the
desired class-scoped binding -- it xpasses (forcing removal) when the class engine
namespaces body assignments to the class.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "cbody.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_class_body_bare_assign_leaks_global(tmp_path):
  # CHARACTERIZATION (the bug, pinned): once an instance stamps the body, the
  # bare assignment lands in GLOBAL (`$(color)`), not on the class (`$(widget.color)`).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| color:=blue |)\n"
    "widget w(| |)\n"
    "probe:; @printf 'cls=[%s] glob=[%s]\\n' '$(widget.color)' '$(color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "cls=[] glob=[blue]" in out, out


@pytest.mark.xfail(reason=(
  "a bare class-body assignment of EITHER form (`=` or `:=`) leaks to the GLOBAL "
  "namespace instead of binding a class attribute (Python: `class Foo: bar=baz` -> "
  "Foo.bar).  Two classes' `fmtentry:=X` clobber one global; code.compiled reads "
  "spec as $(<class>.fmtentry)"), strict=True)
def test_class_body_bare_assign_binds_class_attr(tmp_path):
  # DESIRED: a body assignment binds the CLASS attribute, per-class, no global
  # collision -- broken for both `:=` (walrus) and `=` (plain).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| color:=blue |)\n"
    "cmk.class gizmo(| color=red |)\n"
    "probe:; @printf 'w=[%s] g=[%s]' '$(widget.color)' '$(gizmo.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "w=[blue] g=[red]" in out, out
