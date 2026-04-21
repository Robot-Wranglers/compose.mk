"""The feature x context x indent MATRIX -- the detector the dedent fuzzer should have been.

`fuzz_dedent.py` fuzzed ONE stage (dedent) with plain-shell recipes in `*[|` nests only, so it
never crossed LANGUAGE FEATURES (handle-assign `<-`, member docstrings) with nesting, and never
touched `*(|` (paren) forms -- which is why it reported "no gap" while `__hosted__` (a heavy user
of nested paren bananas) took the blame.  This matrix runs each feature end-to-end through the real
compiler (via the `sandbox` bench) in every nesting context, and pins the pass/fail of every cell.

HISTORY: initially every failure was in a PAREN `(| .. |)` form (paren was raw; square `[|` cooked),
so recipe-level features nested in a paren banana were left unprocessed by the later stages.  FIXED
2026-07-20 in `.awk.sugarawk` frame_emit: a constructor / dissolve-ambient banana now COOKS its body
regardless of bracket, so `(|` and `[|` are uniform.  Every cell now PASSES; `EXPECT` is all-True and
is the regression net -- if any cell regresses to False, the fix (or a stage's ambient-descent) broke.
"""

import pytest

SENT = "MATRIX_OK"

FEATURES = {
  "plain": lambda tgt, I: [f"{tgt}:; @echo {SENT}"],
  "handle": lambda tgt, I: [f"{tgt}:", f"{I}r <- echo {SENT}", f"{I}@echo $${{r}}"],
  "docstring": lambda tgt, I: [f"{tgt}:", f"{I}'''a doc'''", f"{I}@echo {SENT}"],
  "multiline": lambda tgt, I: [f"{tgt}:", f"{I}case x in \\", f"{I}{I}x) echo {SENT};; \\", f"{I}esac"],
}

# (opener, closer, is_class) -- a class needs an instance + a `probe:` alias onto the member.
CONTEXTS = {
  "flat": (None, None, False),
  "amb_paren": ("*(|", "|)", False),
  "amb_square": ("*[|", "|]", False),
  "cls_paren": ("cmk.class K(|", "|)", True),
  "cls_square": ("cmk.class K[|", "|]", True),
}

# Rows exercised (feature, indent-label).  `plain` is single-line (indent N/A).
ROWS = [
  ("plain", "-"), ("handle", "tab"), ("handle", "spc"),
  ("docstring", "spc"), ("multiline", "tab"), ("multiline", "spc"),
]

# Expected `works?` per (feature, indent, context).  All-True since the paren-cook fix: a language
# feature behaves identically in every nesting context.  (Pre-fix, the paren forms held False cells.)
_ALL = {"flat": True, "amb_paren": True, "amb_square": True, "cls_paren": True, "cls_square": True}
EXPECT = {row: dict(_ALL) for row in [
  ("plain", "-"), ("handle", "tab"), ("handle", "spc"),
  ("docstring", "spc"), ("multiline", "tab"), ("multiline", "spc"),
]}


def _build(feature, indent_label, ctx):
  I = "\t" if indent_label == "tab" else "    "
  opener, closer, is_class = CONTEXTS[ctx]
  if ctx == "flat":
    return "\n".join(FEATURES[feature]("probe", I))
  if not is_class:
    lines = FEATURES[feature]("probe", I)
    return opener + "\n" + "\n".join("  " + l for l in lines) + "\n" + closer
  lines = FEATURES[feature]("${self}.go", I)
  return (opener + "\n" + "\n".join("  " + l for l in lines) + "\n" + closer
          + "\nK k1(| |)\nprobe: k1.go")


@pytest.mark.unit
@pytest.mark.parametrize("feature,indent", ROWS)
@pytest.mark.parametrize("ctx", list(CONTEXTS))
def test_nesting_matrix(sandbox, feature, indent, ctx):
  expected = EXPECT[(feature, indent)][ctx]
  r = sandbox.run(_build(feature, indent, ctx), goal="probe")
  works = SENT in r.output
  assert works == expected, (
    f"{feature}/{indent} in {ctx}: expected works={expected}, got works={works}\n{r.output}"
  )
