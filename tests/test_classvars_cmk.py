"""Coverage for `classvars=` metaclass CLASSVARS (protocol, class, AND dsl).

`classvars='__key__=val __bare__'` on a protocol/class/dsl declaration declares a
CLASSVAR per name -- stored NAMESPACED on the class (never a global):
  * `__color__=blue`  -> stores `<Class>.__color__ := blue` (the value);
  * bare `__bare__`   -> declares the name only (a conformer supplies the value).
Each name is recorded in `<Class>.__classvars__`.  Two accessors resolve it:
  * EXTERNAL  `<Class>.__var__`  -- read the value off the class directly;
  * INTERNAL  `self.__var__`     -- inside a recipe, via a per-instance
                                   read-through the minter stamps at construction.
The value resolves up the type closure (own > bases > ifaces), so a base or
protocol default is inherited and a derived class can override it.  Docker-free.
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
  f = tmp_path / "classvars.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_classvar_literal_is_namespaced_not_global(tmp_path):
  # `key=val` stores the value ON THE CLASS (external accessor), and is NOT a
  # global -- a bare `$(__color__)` read stays empty.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='__color__=blue')[| |]\n"
    "demo:; @printf 'cls=[%s] global=[%s]' '$(widget.__color__)' '$(__color__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "cls=[blue]" in out, out
  assert "global=[]" in out, out            # NOT a global accessor


def test_classvar_internal_readthrough(tmp_path):
  # inside an instance recipe, self.<var> resolves the classvar via the
  # per-instance read-through the minter stamps at construction.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='__color__=blue')[|\n"
    "  ${self}.show:; @printf 'A=[%s] B=[%s]' '$(self.__color__)' '$(${self}.__color__)'\n"
    "|]\n"
    "cmk.widget(w)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "A=[blue]" in out, out            # self.<var> read-through inside a recipe
  assert "B=[blue]" in out, out            # ${self}.<var> instance member


def test_classvar_polymorphic(tmp_path):
  # the SAME classvar name yields each class's own value, on the class and on
  # its instances (proves it is namespaced per class, not shared).
  r, out = _run_cmk(
    "from cmk import class\n"
    "class red(classvars='__hue__=crimson')[| |]\n"
    "class blue(classvars='__hue__=azure')[| |]\n"
    "cmk.red(r1)\n"
    "cmk.blue(b1)\n"
    "demo:; @printf 'r=[%s] b=[%s] ri=[%s] bi=[%s]' "
    "'$(red.__hue__)' '$(blue.__hue__)' '$(r1.__hue__)' '$(b1.__hue__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "r=[crimson] b=[azure] ri=[crimson] bi=[azure]" in out, out


def test_classvar_inherited_and_overridden(tmp_path):
  # a protocol default is INHERITED by a conformer (own > bases > ifaces),
  # and a conformer may OVERRIDE it with its own classvars=.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Painted(dunder=__p__ classvars='__color__=blue')(| |)\n"
    "class Foo(ifaces=Painted)[| |]\n"
    "class Bar(ifaces=Painted classvars='__color__=red')[| |]\n"
    "cmk.Foo(foo)\n"
    "cmk.Bar(bar)\n"
    "demo:; @printf 'inherit=[%s] override=[%s]' '$(foo.__color__)' '$(bar.__color__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "inherit=[blue]" in out, out
  assert "override=[red]" in out, out


def test_classvar_on_dsl(tmp_path):
  # classvars= is forwarded through the dsl factory: a dsl declares a classvar,
  # readable externally and via each instance's read-through.
  r, out = _run_cmk(
    "from cmk import dsl\n"
    "dsl lang(entrypoint=true classvars='__lang__=.py')(| |)\n"
    "lang frag(| body |)\n"
    "demo:; @printf 'cls=[%s] inst=[%s]' '$(lang.__lang__)' '$(frag.__lang__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "cls=[.py]" in out, out
  assert "inst=[.py]" in out, out


def test_classvars_quote_aware_multi(tmp_path):
  # the quote-aware parser: a spaced quoted value splits into MULTIPLE classvars
  # (a non-quote-aware get would stop at the first space -> only __a__ minted).
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='__a__=1 __b__=2 __c__=3')[| |]\n"
    "demo:; @printf 'a=[%s] b=[%s] c=[%s]' "
    "'$(widget.__a__)' '$(widget.__b__)' '$(widget.__c__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "a=[1] b=[2] c=[3]" in out, out


def test_classvars_not_mistaken_for_base(tmp_path):
  # classvars= must be filtered from the class base list -- else it is treated as a
  # positional base and warns `undefined variable 'classvars=....__targets__'`.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='__x__=1')[| |]\n"
    "cmk.widget(w)\n"
    "demo:; @printf 'x=[%s]' '$(widget.__x__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "undefined variable 'classvars" not in out, out   # not treated as a base
  assert "x=[1]" in out, out                            # classvar still minted


def test_classvar_bare_body_lowering(tmp_path):
  # cook-stage sugar: a BARE `name = val` line in a class body lowers to a
  # classvar (peer to self->${self}); self-prefixed members are left untouched.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  color = blue\n"
    "  ${self}.__reflect__ = kept\n"
    "  ${self}.show:; @printf 'color=[%s] reflect=[%s] reg=[%s]' "
    "'$(self.color)' '$(${self}.__reflect__)' '$(${self}.__classvars__)'\n"
    "|]\n"
    "cmk.widget(w)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "color=[blue]" in out, out          # bare line lowered to a classvar
  assert "reflect=[kept]" in out, out        # self-prefixed member untouched
  assert "reg=[color]" in out, out           # registered
