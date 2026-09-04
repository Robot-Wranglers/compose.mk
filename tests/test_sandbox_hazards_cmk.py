"""Empirical verification, through the `sandbox` bench, of the recorded `__hosted__`
docstring/dedent HAZARD claims (memory notes `moduledoc-define-endef-hazard` and
`dedent-nesting-aware-fix`).  Each test injects the hazard and asserts the ACTUAL current
behavior -- a claim that still holds is pinned; one that has DRIFTED (e.g. a compiler-stage
reorder) is caught here and becomes the corrected source of truth.

Verified 2026-07-20: `define`/`endef`- and unbalanced-paren-in-docstring STILL break; the
`this.`-in-docstring and `<-`-requires-TAB caveats have DRIFTED (see the `_drifted_` tests),
and the memory was corrected to match.
"""

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.docstring]


def _class_with_doc(doc):
  # A cooked class whose (single-line) docstring is `doc`, plus a probe that echoes the class's
  # always-lifted `W.__doc__` (name-scoped) -- the vehicle for exercising docstring lowering hazards.
  return (
    "cmk.class W(|\n"
    "  '''%s'''\n"
    "  ${self}.x := 1\n"
    "|)\n"
    "W w1(| |)\n"
    "probe:\n"
    "\t@echo [${W.__doc__}]"
  ) % doc


# --- CONFIRMED hazards (the memory still holds) -------------------------------------------


def test_define_in_docstring_breaks_at_run(sandbox):
  # moduledoc-define-endef-hazard: a docstring LINE whose first token is `define`/`endef` lands in
  # the `define ${self}.__doc__ .. endef` wrapper as a nested/closing directive -> make can't parse
  # it.  Note the transpile itself SUCCEEDS (a cache is produced); the break is at make-parse time,
  # so `cmk compile` passing is NOT enough -- exactly the memory's warning.
  body = (
    "cmk.class W(|\n"
    "  '''\n"
    "  an intro line\n"
    "  define foo\n"
    "  '''\n"
    "  ${self}.x := 1\n"
    "|)\n"
    "W w1(| |)\n"
    "probe:\n\t@echo [${w1.__doc__}]"
  )
  r = sandbox.run(body, goal="probe")
  assert not r.ok, r.output
  assert "unterminated 'define'" in r.output or "missing 'endef'" in r.output, r.output


def test_define_mid_sentence_in_docstring_is_safe(sandbox):
  # ... but `define` NOT at line-start is safe (make only recognizes directives at line-start).
  r = sandbox.run(_class_with_doc("you can define things mid sentence"), goal="probe")
  assert r.ok, r.output
  assert "define things mid sentence" in r.stdout, r.output


def test_unbalanced_paren_in_docstring_breaks_eval(sandbox):
  # dedent-nesting-aware-fix caveat: an unbalanced `(`/`)` in docstring PROSE corrupts the
  # `$(eval define ${self}.__doc__ ..)` reification.  CONFIRMED still true.
  r = sandbox.run(_class_with_doc("prose with an unbalanced ( paren"), goal="probe")
  assert not r.ok, r.output
  assert "unterminated call to function 'eval'" in r.output, r.output


# --- DRIFTED caveats (the memory is now STALE; these pin the corrected reality) ------------


def test_drifted_this_dot_in_docstring_no_longer_breaks(sandbox):
  # dedent-nesting-aware-fix claimed `this.` in docstring prose CORRUPTS the wrapper.  DRIFTED: it
  # no longer breaks (rc 0).  Instead the `this.` token is rewritten (dialect), silently MANGLING
  # the stored doc -- a content hazard, not a parse break.  Memory updated to match.
  r = sandbox.run(_class_with_doc("see this.member ok"), goal="probe")
  assert r.ok, r.output  # PRIMARY drift: it does not break anymore
  assert "this.member" not in r.stdout, r.output  # the token was rewritten (content mangled)


def test_drifted_simple_arrow_capture_works_space_indented(sandbox):
  # dedent-nesting-aware-fix claimed ALL `<-` captures REQUIRE TAB.  DRIFTED for the SIMPLE shell
  # form (`x <- cmd`): `lang.comp.stages` now runs `capture` AFTER `indent`, so a SPACE-indented
  # simple capture is re-tabbed first and captures fine.
  r = sandbox.run("probe:\n  r <- echo viaSPACE\n  @echo got=[$${r}]", goal="probe")
  assert r.ok, r.output
  assert "got=[viaSPACE]" in r.stdout, r.output


def test_banana_capture_still_requires_tab(sandbox):
  # ... BUT the BANANA capture `x <- (| body |)` STILL requires TAB (NOT drifted): the tab is the
  # recipe-capture-vs-module-assignment detection key.  TAB works; a SPACE-indented banana capture
  # is misdetected as a module assignment (its lifted `define __cap_N` + `x := $(shell..)` land at
  # col 0) -> `recipe commences before first target`.  (This corrects the earlier over-broad note
  # that "`<-` no longer needs tab" -- true only for the simple shell form, not the banana form.)
  tab = sandbox.run("probe:\n\th <- (| echo banana-body |)\n\t@echo got=[$${h}]", goal="probe")
  assert tab.ok, tab.output
  assert "got=[banana-body]" in tab.stdout, tab.output
  space = sandbox.run("probe:\n  h <- (| echo banana-body |)\n  @echo got=[$${h}]", goal="probe")
  assert not space.ok, space.output
  assert "recipe commences before first target" in space.output, space.output
