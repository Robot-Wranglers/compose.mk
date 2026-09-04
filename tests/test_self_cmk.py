"""Behavior contract for the `self.` desugar in class/protocol bodies.

A cmk class/protocol body may write bare `self` / `self.X` for `${self}` /
`${self}.X`; the class stamp compiles it (a "transpilation in miniature") so
that, per-instance:

  * `self.X:` / `self.X :=` / `self.X =`  (a NAME)  -> `${self}.X`
  * a READ of `self.X` in a recipe/value  (a VALUE) -> `$(${self}.X)`
  * `$(self.X)` / `${self.X}` (already wrapped)      -> value, no double-wrap
  * bare `self` (the instance name, a word) -> `${self}` (the instance name)

These are REAL unit tests: each builds an inline `.cmk` and asserts on the
recipe output -- no demo files (the `Language` protocol these grew from is
being promoted to core, so the contract must stand on its own).  The contract
is IMPL-AGNOSTIC (it must hold whether the stamp uses sed or pure make), so it
pins the two things a naive rewrite gets wrong: WORD-SAFETY (`myself`/`itself`
untouched) and PREFIX-SAFETY (`self.a` vs `self.ab` bounded independently).
Scope is guarded by `__raw_body__` (foreign source untouched) and by being
capture-scoped (top-level `self.X` targets untouched).  Docker-free.
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
  f = tmp_path / "selftest.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


# ── names: heads and assignments desugar to `${self}.X` ──────────────────────

def test_self_head_target_runs(tmp_path):
  # `self.X:` is a recipe head -> the per-instance target `${self}.X`.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(| self.show:; @echo shown |)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "shown" in out, out


def test_self_assign_lhs_both_operators(tmp_path):
  # `self.X :=` (immediate) and `self.X =` (recursive) are both NAME (LHS)
  # positions -> `${self}.X`; read them back to prove the attr was set.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.imm := II\n"
    "  self.rec = RR\n"
    "  self.show:; @printf 'imm=[%s] rec=[%s]' '$(self.imm)' '$(self.rec)'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "imm=[II] rec=[RR]" in out, out


# ── reads: bare / bracketed / wrapped all resolve to the VALUE ────────────────

def test_self_bare_read_compiles_to_value(tmp_path):
  # THE core new behavior: a BARE self.X in a recipe command (no $()) compiles
  # to the value read, not the name -- what a plain $(subst) cannot generate.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__)(|\n"
    "  self.show:; @echo 'matcher=self.__lang__ name=self'\n"
    "|)\n"
    "class Foo(ifaces=P)[| self.__lang__ := go |]\n"
    "cmk.Foo(f)\n"
    "__main__: f.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "matcher=go" in out, out          # bare read -> value
  assert "name=f" in out, out              # bare self -> instance name


def test_self_read_forms_equivalent(tmp_path):
  # bare / bracketed / paren-wrapped / brace-wrapped reads all yield the value
  # (the wrapped forms must NOT double-wrap into $($(...)) -> empty).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.a := AAA\n"
    "  self.show:; @printf 'bare=[%s] brk=[%s] paren=[%s] brace=[%s]' "
    "'k=self.a' '[self.a]' '$(self.a)' '${self.a}'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "bare=[k=AAA]" in out, out
  assert "brk=[[AAA]]" in out, out
  assert "paren=[AAA]" in out, out
  assert "brace=[AAA]" in out, out


def test_self_multiple_and_duplicate_reads(tmp_path):
  # several distinct members on one line, and the same member twice.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.a := AAA\n"
    "  self.b := BBB\n"
    "  self.show:; @printf 'multi=[%s %s] dup=[%s %s]' "
    "'self.a' 'self.b' 'self.a' 'self.a'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "multi=[AAA BBB]" in out, out
  assert "dup=[AAA AAA]" in out, out


def test_self_head_and_read_on_same_line(tmp_path):
  # the head before `:` is a NAME; a read after it (in the recipe) is a VALUE.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.lang := go\n"
    "  self.build:; @echo 'target=$(@) using=self.lang'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.build\n", tmp_path)
  assert r.returncode == 0, out
  assert "target=w.build" in out, out      # head -> ${self}.build target name
  assert "using=go" in out, out            # read -> value


# ── the instance name: bare `self` word ──────────────────────────────────────

def test_self_bare_name_contexts(tmp_path):
  # bare `self` (a word) is the instance NAME across delimiter contexts.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.show:; @printf 'word=[%s] slash=[%s] eq=[%s]' "
    "'self' 'p/self' 'n=self'\n"
    "|)\n"
    "widget inst(| |)\n"
    "__main__: inst.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "word=[inst]" in out, out
  assert "slash=[p/inst]" in out, out
  assert "eq=[n=inst]" in out, out


# ── the two things a naive rewrite breaks ────────────────────────────────────

def test_self_is_word_safe(tmp_path):
  # `self` as a SUBSTRING of another identifier is NOT the instance token:
  # myself / itself / self_x / selfish must be left verbatim.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.a := AAA\n"
    "  self.show:; @printf 'ws=[%s]' 'myself itself self_x selfish self.a'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "ws=[myself itself self_x selfish AAA]" in out, out


def test_self_members_are_prefix_safe(tmp_path):
  # a short member must not eat a longer one: self.a vs self.ab are bounded
  # independently (a $(subst self.a) would corrupt self.ab).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  self.a := AAA\n"
    "  self.ab := ABAB\n"
    "  self.show:; @printf 'pfx=[%s | %s]' 'self.a' 'self.ab'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "pfx=[AAA | ABAB]" in out, out


# ── scope: what must be left ALONE ───────────────────────────────────────────

def test_self_explicit_ref_preserved(tmp_path):
  # an explicit `${self}` / `${self}.X` in the body still works alongside the
  # bare forms (the desugar must not corrupt an already-expanded ref).
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class widget(|\n"
    "  ${self}.a := AAA\n"
    "  self.show:; @printf 'exp=[%s] bare=[%s]' '$(${self}.a)' 'self.a'\n"
    "|)\n"
    "widget w(| |)\n"
    "__main__: w.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "exp=[AAA] bare=[AAA]" in out, out


def test_self_raw_body_untouched(tmp_path):
  # a raw code-object body (Python self.) must NOT be desugared.
  r, out = _run_cmk(
    "code pycode(|\n"
    "  def m(self):\n"
    "    return self.value\n"
    "|)\n"
    "probe:; ${mk.def.read}/pycode\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "return self.value" in out, out          # raw self. preserved
  assert "${self}.value" not in out, out          # NOT desugared
  assert "$(${self}" not in out, out              # NOT wrapped as a read


def test_self_top_level_target_unaffected(tmp_path):
  # a top-level `self.X:` (not a class body) is the in-container dispatch
  # convention; the desugar is capture-scoped, so it is left alone.
  r, out = _run_cmk(
    "self.run:; @echo ran-self-target\n"
    "__main__: self.run\n", tmp_path)
  assert r.returncode == 0, out
  assert "ran-self-target" in out, out


# ── composition: protocol fold, base inheritance, polymorphism ───────────────

def test_self_via_ifaces_protocol(tmp_path):
  # a protocol body using self. folds onto a conformer via ifaces= and desugars
  # there (proves the desugar reaches the protocol-mixin path, not just own).
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__)(|\n"
    "  self.greet:; @printf 'greet=[%s] lang=[%s]' '$(@)' 'x=self.lang'\n"
    "|)\n"
    "class Foo(ifaces=P)[| self.lang := go |]\n"
    "cmk.Foo(f)\n"
    "__main__: f.greet\n", tmp_path)
  assert r.returncode == 0, out
  assert "greet=[f.greet]" in out, out
  assert "lang=[x=go]" in out, out


def test_self_via_class_base(tmp_path):
  # self. in a BASE class body reaches a subclass instance.
  r, out = _run_cmk(
    "from cmk import class\n"
    "cmk.class Base(| self.hi:; @echo hi-from-base |)\n"
    "cmk.class Sub(bases=Base)(| |)\n"
    "Sub s(| |)\n"
    "__main__: s.hi\n", tmp_path)
  assert r.returncode == 0, out
  assert "hi-from-base" in out, out


def test_self_read_is_polymorphic(tmp_path):
  # a bare self. read is self-relative: the SAME method yields each instance's
  # own stored attr (proves recipe-time self, not a value baked at stamp).
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__)(|\n"
    "  self.show:; @printf '$(@)=[%s] ' 'self.lang'\n"
    "|)\n"
    "class Foo(ifaces=P)[| self.lang := go |]\n"
    "class Bar(ifaces=P)[| self.lang := py |]\n"
    "cmk.Foo(f)\n"
    "cmk.Bar(b)\n"
    "__main__: f.show b.show\n", tmp_path)
  assert r.returncode == 0, out
  assert "f.show=[go]" in out, out
  assert "b.show=[py]" in out, out
