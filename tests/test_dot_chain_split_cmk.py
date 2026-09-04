"""A banana dot-chain may be split across lines after an operand's close.

The multiline dot-chain (`foo(| a |).bar(| b |)`, see demos/cmk/banana-fluent.cmk and
demos/cmk/bash-if.cmk) is lifted in the `sugar` stage's frame system.  A chain step
`.ctor(| .. |)` that sits on the SAME line as the preceding operand's close has always
lifted; this pins the SPLIT form, where the operand closes and the chain resumes with a
leading-dot on the NEXT line:

    bif(| cond |)          # operand closed inline...
    .then(| body |)        # ...chain resumes here

and the multiline-operand variant:

    bif(|
      cond
    |)                     # operand closed on its own line...
    .then(| body |)        # ...chain resumes here

Both are folded by parking the closed frame (the `awaitd` deferral) and resuming the
dot-chain when the next line is a leading-dot banana open.  Before the fix a split chain
mis-lowered: the head operand became a STANDALONE `define bif` (clobbering the ctor) and
the leading-dot line a `define .then`, so the chain never formed (`recipe commences before
first target`).  The same-line and all-inline forms are guarded here too, so the fold
cannot regress them.
"""

import pytest

pytestmark = pytest.mark.compiler


# A self-contained `bif` builder (the demos/cmk/bash-if.cmk idiom): __ops__ accumulates the
# operands, __call__ assembles a real `if .. fi` and sources it (so a then-branch runs).
_BIF = (
  "from cmk import constructor\n"
  "constructor then[||]\n"
  "constructor else[||]\n"
  "constructor bif[|\n"
  "  ${self}.__ops__ := ${self}\n"
  "  ${self}.__dot__ = $(eval ${self}.__ops__ += ${__args__})${self}\n"
  "  ${self}.__call__ = . <({ printf 'if '; $(call _mk.def.to.fd,$(word 1,$(${self}.__ops__))); printf '\\nthen\\n'; $(call _mk.def.to.fd,$(word 2,$(${self}.__ops__))); $(if $(word 3,$(${self}.__ops__)),printf '\\nelse\\n'; $(call _mk.def.to.fd,$(word 3,$(${self}.__ops__)));) printf '\\nfi\\n'; })\n"
  "|]\n"
)

# Each shape is a `__main__` recipe over the same chain (cond true -> the then-branch runs
# and prints REACHED; the else-branch, when present, must NOT run).  The four differ only in
# WHERE the operands close and where the chain resumes.
_SHAPES = {
  # SPLIT: op1 closes inline, `.then` resumes on the next line, multiline clauses.
  "split_inline_head": (
    "__main__:\n"
    "\tbif(| true |)\n"
    "\t.then(|\n"
    "\t  echo REACHED\n"
    "\t|).else(|\n"
    "\t  echo NOPE\n"
    "\t|)\n"
  ),
  # SPLIT: op1 closes on its own line (multiline operand), `.then` resumes on the next line.
  "split_multiline_head": (
    "__main__:\n"
    "\tbif(|\n"
    "\t  true\n"
    "\t|)\n"
    "\t.then(| echo REACHED |)\n"
  ),
  # SAME-LINE (regression guard): op1 multiline, `|).then(` on the close line.
  "same_line": (
    "__main__:\n"
    "\tbif(|\n"
    "\t  true\n"
    "\t|).then(| echo REACHED |)\n"
  ),
  # ALL-INLINE (regression guard): the whole chain on one line, plus a following plain
  # recipe line -- pins that a parked single-line banana still finalizes + the next line runs.
  "all_inline": (
    "__main__:\n"
    "\tbif(| true |).then(| echo REACHED |)\n"
    "\techo AFTER\n"
  ),
}


@pytest.mark.parametrize("shape", list(_SHAPES), ids=list(_SHAPES))
def test_split_dot_chain_runs(cmk, tmp_path, shape):
  # end-to-end: the chain forms, sources the assembled `if`, and reaches the then-branch.
  f = tmp_path / "chain.cmk"
  f.write_text(_BIF + _SHAPES[shape])
  r = cmk("cmk", "run", str(f), env={"CMK_SUPERVISOR": "1"})
  assert r.ok, r.stderr
  assert "REACHED" in r.stdout
  assert "NOPE" not in r.stdout  # the else-branch must not run when the condition holds


def test_split_head_is_not_a_standalone_banana(ir):
  # LOWERING guard: a split chain must fold into the dot machinery, NOT mis-lower the head
  # into a standalone `define bif` (the ctor clobber) or the leading-dot line into `define .then`.
  out = ir(_BIF + _SHAPES["split_inline_head"])
  assert "$(call lang.grammar.dot.op" in out  # the fold formed
  assert "define .then" not in out            # the `.then` line did not become a bare define
