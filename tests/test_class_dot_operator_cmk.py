"""The dot operator over `class`- and `bases=`-declared kinds.

The banana dot operator (`foo(| a |).bar(| b |)`, see demos/cmk/banana-fluent.cmk)
lowers to `lang.grammar.dot.new,<ctor>,<op>` instantiations that are folded through
the running operand's `.__dot__` and finally invoked via `.__call__`.

The dispatch spans EVERY kind, not just `constructor`-registered ones.  A dot operand
carries an opaque body (shell text), so `lang.grammar.dot.new` marks it as a raw
payload (`.__raw_body__`) before instantiating -- otherwise the `class` engine's
own-body branch would `$(eval)` the operand body as member code (`echo a` is not
makefile -> `*** missing separator`).  With that marking a `class` kind, and a
builder that inherits its accumulator dunders via `bases=`, both chain exactly like
a self-contained `constructor` -- which is what lets demos/cmk/bash-loops.cmk share
one `bash_compound` base across `bfor`/`bwhile`/`bcase`.

The `constructor` control guards the always-worked path; the `class`/`bases=` cases
guard the dispatch reaching every kind.
"""

import pytest

pytestmark = pytest.mark.compiler


def run_cmk(cmk, tmp_path, src):
  """Write `src` to a temp .cmk and run it through `cmk run` (real dispatch, the
  path that exercises dot-operator instantiation + fold + invoke)."""
  f = tmp_path / "chain.cmk"
  f.write_text(src)
  return cmk("cmk", "run", str(f), env={"CMK_SUPERVISOR": "1"})


# A fluent kind whose body is the SAME for both keywords -- only the registration
# keyword (`constructor` vs `class`) differs.  `__cmd__` seeds from the first
# operand, `__dot__` appends each rhs with ` ; `, `__call__` runs the accumulation.
_SEQ_BODY = (
  "{kw} seq[|\n"
  "  ${{self}}.__cmd__ := $(value ${{self}})\n"
  "  ${{self}}.__dot__ = $(eval ${{self}}.__cmd__ := ${{self}}.__cmd__() ; $(value ${{__args__}}))${{self}}\n"
  "  ${{self}}.__call__ = ${{self}}.__cmd__()\n"
  "|]\n"
  "__main__:\n"
  "\tseq(| echo LHS |).seq(| echo RHS |)\n"
)


def test_constructor_dot_chain_control(cmk, tmp_path):
  # CONTROL (works today): a `constructor`-declared fluent kind chains via the dot
  # operator and runs both operands.  This is the path bash-if.cmk was migrated to.
  src = "from cmk import constructor\n" + _SEQ_BODY.format(kw="constructor")
  r = run_cmk(cmk, tmp_path, src)
  assert r.ok, r.stderr
  assert "LHS" in r.stdout and "RHS" in r.stdout


def test_class_dot_chain(cmk, tmp_path):
  # the IDENTICAL fluent kind registered with `class` chains and runs exactly like
  # the `constructor` control above (the raw-payload marking keeps the class engine
  # from eval-ing each operand's opaque body as member code).
  src = "from cmk import class\n" + _SEQ_BODY.format(kw="class")
  r = run_cmk(cmk, tmp_path, src)
  assert r.ok, r.stderr
  assert "LHS" in r.stdout and "RHS" in r.stdout


# The bash-if / bash-loops shape: a shared accumulator base + a builder that derives
# it and adds only its own `__call__` assembler (here: a real `if .. fi` sourced
# inline).  `bif` inherits `__dot__`/`__ops__` from `bash_compound` via `bases=`.
_BASES_SRC = (
  "from cmk import constructor, class\n"
  "class bash_compound[|\n"
  "  ${self}.__ops__ := ${self}\n"
  "  ${self}.__dot__ = $(eval ${self}.__ops__ += ${__args__})${self}\n"
  "|]\n"
  "class bif(bases=bash_compound)[|\n"
  "  ${self}.__call__ = . <({ printf 'if '; $(call _mk.def.to.fd,$(word 1,$(${self}.__ops__))); printf '\\nthen\\n'; $(call _mk.def.to.fd,$(word 2,$(${self}.__ops__))); printf '\\nfi\\n'; })\n"
  "|]\n"
  "constructor then[||]\n"
  "__main__:\n"
  "\tbif(| true |).then(| echo BASES_REACHED |)\n"
)


def test_bases_inherited_dunders_dot_chain(cmk, tmp_path):
  # a builder that INHERITS `__dot__` from a base via `bases=` chains, assembles the
  # real `if .. fi`, sources it, and reaches the then-branch.
  r = run_cmk(cmk, tmp_path, _BASES_SRC)
  assert r.ok, r.stderr
  assert "BASES_REACHED" in r.stdout


# The bash-loops motivation: ONE `bash_compound` base SHARED by TWO builders, each
# adding only its own `__call__`.  This is the reuse the dispatch unlocks and that the
# `constructor`-inline workaround cannot express (the accumulator would otherwise have
# to be hand-copied into every builder).
_SHARED_BASE_SRC = (
  "from cmk import constructor, class\n"
  "class bash_compound[|\n"
  "  ${self}.__ops__ := ${self}\n"
  "  ${self}.__dot__ = $(eval ${self}.__ops__ += ${__args__})${self}\n"
  "|]\n"
  "class bif(bases=bash_compound)[|\n"
  "  ${self}.__call__ = . <({ printf 'if '; $(call _mk.def.to.fd,$(word 1,$(${self}.__ops__))); printf '\\nthen\\n'; $(call _mk.def.to.fd,$(word 2,$(${self}.__ops__))); printf '\\nfi\\n'; })\n"
  "|]\n"
  "class bwhile(bases=bash_compound)[|\n"
  "  ${self}.__call__ = . <({ printf 'while '; $(call _mk.def.to.fd,$(word 1,$(${self}.__ops__))); printf '\\ndo\\n'; $(call _mk.def.to.fd,$(word 2,$(${self}.__ops__))); printf '\\ndone\\n'; })\n"
  "|]\n"
  "constructor then[||]\n"
  "constructor do[||]\n"
  "__main__:\n"
  "\tbif(| true |).then(| echo IF_BRANCH |)\n"
  "\tn=1\n"
  "\tbwhile(| [ \"$n\" -gt 0 ] |).do(| echo LOOP_BODY; n=0 |)\n"
)


def test_shared_base_across_builders(cmk, tmp_path):
  # two builders derived from the same base both chain and run.
  r = run_cmk(cmk, tmp_path, _SHARED_BASE_SRC)
  assert r.ok, r.stderr
  assert "IF_BRANCH" in r.stdout and "LOOP_BODY" in r.stdout
