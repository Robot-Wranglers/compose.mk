"""Multi-line recipe indentation inside a cooked-class body, driven through the REAL compiler via
the `sandbox` bench.  This ENCODES (and supersedes) tests/scripts/characterize_hosted_recipe_indent.sh
-- that shell harness existed because "a user file gets the lenient retab; __hosted__ does not", a
path the old pytest suite could not reproduce.  The sandbox bench transpiles through the same
`lang.transpile` pipeline as `__hosted__`, so it reproduces that strict path directly, as pytest.

Characterized 2026-07-20: multi-line recipes in a cooked class body work at any nesting -- TAB in
either banana form, SPACE only in the `[| .. |]` (square) form.  A SPACE-indented multi-line recipe
in a `(| .. |)` (paren) class FAILS (`missing separator`) -- an asymmetry the shell harness missed
(it only tested SPACE in square-banana classes).
"""

import pytest

pytestmark = pytest.mark.unit


def _class(opener, closer, recipe_body):
  # A cooked class `K` with a `${self}.scr` recipe, an instance, and a probe that runs it.
  return (
    "cmk.class K%s\n"
    "  ${self}.scr:\n"
    "%s\n"
    "|%s\n"
    "K k1(| |)\n"
    "probe: k1.scr" % (opener, recipe_body, closer)
  )


# --- The char-script cases: multi-line recipes work in a cooked class body ------------------


def test_single_line_recipe_in_class(sandbox):
  r = sandbox.run("cmk.class K[|\n  ${self}.scr:; @echo SINGLE_OK\n|]\nK k1(| |)\nprobe: k1.scr",
                  goal="probe")
  assert r.ok, r.output
  assert "SINGLE_OK" in r.stdout, r.output


def test_multiline_tab_recipe_square_class(sandbox):
  # TAB-indented multi-line `case..esac` in a `[| .. |]` class.
  body = "\tcase x in \\\n\t\tx) echo TABSQ_OK;; \\\n\tesac"
  r = sandbox.run(_class("[|", "]", body), goal="probe")
  assert r.ok, r.output
  assert "TABSQ_OK" in r.stdout, r.output


def test_multiline_space_recipe_square_class(sandbox):
  # SPACE-indented multi-line `case..esac` in a `[| .. |]` class -- the case the shell harness
  # proved (nesting-aware dedent lands the head at col 0, indent re-tabs).
  body = "    case x in \\\n      x) echo SPCSQ_OK;; \\\n    esac"
  r = sandbox.run(_class("[|", "]", body), goal="probe")
  assert r.ok, r.output
  assert "SPCSQ_OK" in r.stdout, r.output


def test_multiline_tab_recipe_paren_class(sandbox):
  # TAB works in a `(| .. |)` (paren) class too.
  body = "\tcase x in \\\n\t\tx) echo TABPAR_OK;; \\\n\tesac"
  r = sandbox.run(_class("(|", ")", body), goal="probe")
  assert r.ok, r.output
  assert "TABPAR_OK" in r.stdout, r.output


# --- The paren/square asymmetry the shell harness missed -- now FIXED ----------------------


def test_multiline_space_recipe_paren_class_works(sandbox):
  # Previously an ASYMMETRY: a SPACE-indented multi-line recipe in a `(| .. |)` (paren) class used
  # to FAIL (`missing separator`) while the `[| .. |]` (square) form worked.  FIXED 2026-07-20 by
  # cooking constructor bananas (`.awk.sugarawk` frame_emit) so `(|` bodies are transparent to the
  # `indent` re-tab stage, exactly like `[|`.  Now tab OR space works in both forms.
  body = "    case x in \\\n      x) echo SPCPAR_OK;; \\\n    esac"
  r = sandbox.run(_class("(|", ")", body), goal="probe")
  assert r.ok, r.output
  assert "SPCPAR_OK" in r.stdout, r.output
