"""Banana ASSIGNMENT forms and next-line trailers.

A bare (no-name, no-inline-trailer) anonymous block bound via an assignment
operator names the block via its LHS; the OPERATOR picks the treatment:

  NAME  = (| .. |)   RAW    -> verbatim `define NAME`
  NAME := (| .. |)   COOKED -> interior lowered through the cmk compiler
  NAME <- (| .. |)   RUN    -> `NAME := $(shell bash <block>)` (capture stdout)

These are disjoint from the NAMED banana (`name(| .. |)`, a word touches `(|`)
and from lambda-lift (which needs a `{..}`/`(..)` trailer).  Separately, a
multi-line `|)` close may carry its `with`/`using` trailer on FOLLOWING lines.
"""

import pytest

pytestmark = pytest.mark.compiler


# --- `=` : raw recursive define (body verbatim) -----------------------------


def test_assign_eq_is_raw(ir):
  out = ir("X = (| a:; cmk.log(hi) |)\n")
  assert "define X" in out
  assert "cmk.log(hi)" in out  # body stays VERBATIM
  assert "$(call log" not in out  # ...not lowered


def test_assign_eq_multiline_raw(ir):
  out = ir("X = (|\n    a:; cmk.log(x)\n|)\n")
  assert "define X" in out
  assert "cmk.log(x)" in out
  assert "$(call log" not in out


# --- `:=` : cooked recursive define (interior lowered) ----------------------


def test_assign_colon_eq_is_cooked(ir):
  out = ir("X := (| a:; cmk.log(hi) |)\n")
  assert "define X" in out
  assert "$(call log,hi)" in out  # LOWERED
  assert "cmk.log(hi)" not in out


def test_assign_colon_eq_multiline_cooked(ir):
  out = ir("X := (|\n    a:; cmk.log(x)\n|)\n")
  assert "$(call log,x)" in out


def test_assign_cooked_body_is_dedented(ir):
  # REGRESSION: the cooked `:=` body must reach column 0, not carry a leading
  # tab -- else `$(eval $(value X))` reads a tabbed line as a recipe and make
  # dies with "missing separator".  (The dedent stage must see the `:=` opener.)
  out = ir("X := (|\n    a:; @echo hi\n|)\n")
  body = out.define("X")
  assert "\ta:;" not in body  # no leading TAB on the target line
  assert "a:; @echo hi" in body


# --- `<-` : run the block, capture stdout -----------------------------------


def test_assign_capture_runs_and_binds(ir):
  out = ir("X <- (| echo hi |)\n")
  # the block is hoisted to a gensym define + captured via the [stream] path
  assert "define __cap_" in out and "echo hi" in out
  assert "X := $(shell bash $(call _mk.def.tmpfile, __cap_" in out


def test_assign_capture_multiline(ir):
  out = ir("K <- (|\n  uname -s | tr A-Z a-z\n|)\n")
  assert "define __cap_" in out
  assert "uname -s | tr A-Z a-z" in out
  assert "K := $(shell bash $(call _mk.def.tmpfile, __cap_" in out


# --- disjointness: ordinary assignments and NAMED value forms are untouched -


def test_normal_assignments_untouched(ir):
  # no `(|` block => the assignment-form opener must not fire.
  out = ir("X := $(shell echo hi)\nY = foo bar\nZ <- echo run\n")
  assert "X := $(shell echo hi)" in out
  assert "Y = foo bar" in out
  # `Z <- echo run` has no block -> the ordinary capture stage handles it
  assert "Z := $(shell echo run)" in out


def test_named_value_form_is_not_assignment_form(ir):
  # `X := name(| .. |)[S]` has a NAME touching `(|` -> the named [stream] value
  # form, NOT the bare `:=` cooked-define form.
  out = ir("N := up(| tr a-z A-Z |)[echo hi]\n")
  assert "define up" in out
  assert "N := $(shell echo hi | bash $(call _mk.def.tmpfile, up))" in out


# --- next-line trailers (trailer spills past a standalone `|)`) --------------


def test_nextline_using_trailer(ir):
  # `using` on the line AFTER `|)` still threads to the PREFIX constructor.
  out = ir("code.unbound note(|\n  x\n|)\n   using img=alpine\n")
  assert "$(call code.unbound, def=note img=alpine)" in out


def test_nextline_trailer_orphan_using_errors(ir):
  # a next-line `using` with NO prefix constructor is still the orphan error.
  out = ir("note(|\n  x\n|)\n   using img=alpine\n")
  assert "$(error" in out and "`using`" in out


def test_blank_line_terminates_nextline_trailer(ir):
  # a blank line after `|)` ends the trailer; the following target is normal.
  out = ir("code.unbound note(|\n  x\n|)\n\ndemo:; @echo ok\n")
  assert "$(call code.unbound, def=note)" in out
  assert "demo:; @echo ok" in out
