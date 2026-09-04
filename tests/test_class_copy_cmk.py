"""Coverage for `lang.class.copy` -- the poor-man's class copy.

A plain `class` gets neither `__ctor_src__` nor `__ctor_copy__` (the class path
skips the ctor reifier), so it is not copyable via the code-object `.copy()` machinery.
`lang.class.copy` fills the gap with zero new construction plumbing: it rebuilds the
destination from the body (`__mixin`) and kwargs (`__ctor_initkw__`) the class already
stashes, re-running `lang.class!` under the new name.

`$(call lang.class.copy,Src,Dst)` yields an independent class (a copy, not an alias):
fresh `__mro__`/classvars/body under `Dst`, and instances report `__class__ = Dst`.
The real `Copyable` protocol (stash `__ctor_src__`, formalize `.copy`) is tracked in
SPIKE-m5.md ## Ideas.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
    f = tmp_path / "copy.cmk"
    f.write_text(body)
    r = subprocess.run(
        [str(COMPOSE), "cmk", "run", str(f), *targets],
        cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
        text=True, errors="replace", timeout=timeout,
    )
    return r, _ANSI.sub("", r.stdout + r.stderr)


_SRC = (
    "from cmk import class\n"
    "class Foo(classvars='k=v')[| ${self}.tag := from-foo |]\n"
    "$(call lang.class.copy,Foo,Bar)\n"
    "Bar b1[| |]\n"
    "Foo f1[| |]\n"
    "demo:; @printf 'BAR_MRO=[%s] BAR_K=[%s] B1_TAG=[%s] B1_CLASS=[%s] "
    "FOO_MRO=[%s] F1_CLASS=[%s]\\n' "
    "'$(Bar.__mro__)' '$(Bar.k)' '$(b1.tag)' '$(b1.__class__)' "
    "'$(Foo.__mro__)' '$(f1.__class__)'\n"
)


def _fields(out):
    return dict(re.findall(r"(\w+)=\[([^\]]*)\]", out))


def test_copy_is_defined_and_independent(tmp_path):
    r, out = _run_cmk(_SRC, tmp_path, "demo")
    assert r.returncode == 0, out
    f = _fields(out)
    # the copy exists with a FRESH mro rooted at the new name (not Foo)
    assert f["BAR_MRO"].split()[0] == "Bar", out
    assert "Foo" not in f["BAR_MRO"], out
    # classvars and body copied
    assert f["BAR_K"] == "v", out
    assert f["B1_TAG"] == "from-foo", out
    # instances of the copy report the NEW class (baked name is fresh, not Foo)
    assert f["B1_CLASS"] == "Bar", out
    # the source is untouched -- a copy, not a mutation
    assert f["FOO_MRO"].split()[0] == "Foo", out
    assert f["F1_CLASS"] == "Foo", out
