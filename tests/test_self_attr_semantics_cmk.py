"""Attribute SEMANTICS of `self.X` in class/protocol bodies -- characterization
plus the desired-but-unbuilt contract (mostly xfail).

The `self.` desugar is purely SYNTACTIC: `self.X` (read) lowers to
`$(${self}.X)`, a make variable read -- and make reads are TOTAL (an undefined
variable yields ""). So today `self.X` is defined for *every* X and returns ""
by default: there is no cmk analogue of Python's `AttributeError`.  That is a
big footgun -- a forgotten conformance attribute, or a typo'd dunder, silently
reads empty instead of failing.

`props=` is the complementary, DECLARATION half (which names are real
properties), but it is not yet wired to gate `self.X` access -- a declared
property and a garbage name read identically.

The tests below split into two groups:
  * PASS -- pin the CURRENT reality (total/empty reads; assignment works; props=
    does not gate).  These lock the footgun so a fix is a deliberate, visible
    change.
  * XFAIL(strict) -- the DESIRED contract: an undeclared / typo'd / unset
    property access should FAULT, not empty.  Each `reason` is the spec; when
    the guard lands the xpass forces the xfail off.  Docker-free.
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
  f = tmp_path / "attr.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


# ═══════════════════════════════════════════════════════════════════════════
# CHARACTERIZATION -- the current (footgun-bearing) reality, pinned as PASS.
# ═══════════════════════════════════════════════════════════════════════════

def test_read_unset_attr_is_empty_not_error(tmp_path):
  # a never-set self.X read lowers to a total make read -> "" (rc 0, no fault).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| self.show:; @printf 'v=[%s] ok' 'self.unset' |)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "v=[] ok" in out, out


def test_read_typo_and_arbitrary_names_all_empty(tmp_path):
  # `self.X` is defined for EVERY X: a typo of a set attr, a garbage name, and a
  # deep dotted path all read "" with rc 0 -- nothing distinguishes them.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.value := V\n"
    "  self.show:; @printf 'typo=[%s] junk=[%s] deep=[%s]' "
    "'self.vlaue' 'self.zzz_nope' 'self.a.b.c'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "typo=[] junk=[] deep=[]" in out, out


def test_assign_roundtrips_immediate_and_recursive(tmp_path):
  # `self.X = ..` IS defined: it lowers to `${self}.X = ..` and sets a real
  # per-instance variable, readable back (both := and = operators).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.imm := II\n"
    "  self.rec = RR\n"
    "  self.show:; @printf 'imm=[%s] rec=[%s]' 'self.imm' 'self.rec'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "imm=[II] rec=[RR]" in out, out


def test_assign_sets_only_the_named_attr(tmp_path):
  # assigning self.a does NOT make a sibling self.b readable -- assignment is a
  # per-name var set, not a namespace/property declaration.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.a := AAA\n"
    "  self.show:; @printf 'a=[%s] b=[%s]' 'self.a' 'self.b'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "a=[AAA] b=[]" in out, out


def test_props_declared_does_not_gate_self_reads(tmp_path):
  # props= names the valid property set, but does NOT (yet) gate `self.X`:
  # reading a declared-but-unset prop and an undeclared name both yield "".
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__ props='__lang__')(|\n"
    "  self.show:; @printf 'declared=[%s] undeclared=[%s]' "
    "'self.__lang__' 'self.__bogus__'\n"
    "|)\n"
    "class Foo(ifaces=P)[| |]\n"
    "cmk.Foo(f)\n"
    "__main__: f.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "declared=[] undeclared=[]" in out, out       # indistinguishable


# ═══════════════════════════════════════════════════════════════════════════
# DESIRED CONTRACT -- a cmk AttributeError.  xfail(strict): each fails today
# (rc 0, empty) and will xpass -> force removal when the guard is built.
# ═══════════════════════════════════════════════════════════════════════════

@pytest.mark.xfail(reason=(
  "no cmk AttributeError: reading an undeclared self.X yields '' instead of "
  "faulting -- self.X is total (empty-by-default) for every X"), strict=True)
def test_read_undeclared_property_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| self.show:; @echo 'v=self.never_declared' |)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "typo tolerance: reading self.vlaue (typo of a set self.value) should fault, "
  "not silently read '' -- there is no declared-property set to check against"),
  strict=True)
def test_read_typo_of_set_attr_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.value := V\n"
    "  self.show:; @echo 'x=self.vlaue'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "deep access: self.a.b.c on an instance with no such chain should fault, not "
  "read '' -- there is no attribute-existence check at any depth"), strict=True)
def test_read_deep_dotted_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| self.show:; @echo 'v=self.a.b.c' |)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "props= should GATE self.X: with props='__lang__' declared, reading the "
  "undeclared self.__bogus__ should fault while self.__lang__ resolves"),
  strict=True)
def test_declared_ok_but_undeclared_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__ props='__lang__')(|\n"
    "  self.show:; @echo 'bogus=self.__bogus__'\n"
    "|)\n"
    "class Foo(ifaces=P)[| self.__lang__ := go |]\n"
    "cmk.Foo(f)\n"
    "__main__: f.show\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "conformance: a protocol read of self.__lang__ that the conformer never set "
  "should fault (contract unmet), not silently blank the matcher"), strict=True)
def test_missing_conformance_attr_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Lang(dunder=__l__)(|\n"
    "  self.matcher:; @echo 'm=[self.__lang__]'\n"
    "|)\n"
    "class Impl(ifaces=Lang)[| |]\n"          # forgot self.__lang__ = ..
    "cmk.Impl(i)\n"
    "__main__: i.matcher\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "declared-but-unset: props='__lang__' declares the property, but a conformer "
  "that omits self.__lang__ should fault (or take an explicit default), not "
  "read ''"), strict=True)
def test_props_declared_but_unset_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__ props='__lang__')(|\n"
    "  self.show:; @echo 'lang=[self.__lang__]'\n"
    "|)\n"
    "class Foo(ifaces=P)[| |]\n"              # declared via props=, never set
    "cmk.Foo(f)\n"
    "__main__: f.show\n", tmp_path)
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "concrete footgun: an unset matcher (matcher=self.__lang__ where __lang__ is "
  "unset) should fault rather than run the tool with a blank matcher argument"),
  strict=True)
def test_unset_matcher_should_fault(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class refl(|\n"
    "  self.parse:; @printf 'cmd=[tool --matcher %s]' 'self.__lang__'\n"
    "|)\n"
    "refl r(| |)\n"
    "__main__: r.parse\n", tmp_path)
  # DESIRED: fault on the unset matcher; CURRENT: cmd=[tool --matcher ]
  assert r.returncode != 0, out


@pytest.mark.xfail(reason=(
  "strict declaration: assigning self.X for an X that no props= declared should "
  "require a declaration (or register the property), not silently create a raw "
  "per-instance var indistinguishable from a typo"), strict=True)
def test_assign_to_undeclared_should_require_declaration(tmp_path):
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.undeclared := oops\n"
    "  self.show:; @echo done\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode != 0, out
