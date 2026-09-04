"""User-defined block brackets (the `block_brackets` pragma).

Banana blocks come in three brackets that differ only in how the body is treated:
`(| .. |)` is raw (verbatim, inert data), `[| .. |]` is deep-cooked as live cmk-lang,
and `{| .. |}` is an OPEN slot with no built-in meaning until a `block_brackets` pragma
assigns it a treatment.  A treatment is any stdin->stdout target (a stdlib/plugin `stream.*`
verb); its output becomes the block's value, computed at compile time.

These tests exercise the feature directly with self-contained programs -- they do NOT run
demos/cmk/banana-user-defined.cmk, so they stay valid independent of that demo's wording.

Docker-free (make only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-user-defined.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(src, tmp_path, goal="__main__"):
  f = tmp_path / "bb.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return r, r.stdout + r.stderr


# The brace slot wired to `stream.strip`; a raw paren block alongside as the untreated control.
# The pragma MUST be the first line: the pragma scanner stops at the first non-comment line, so a
# leading blank would hide it (the same footgun that broke demos/cmk/repl.cmk).
STRIP_PROG = r"""# cmk_pragma ::: { "block_brackets": ["{}=stream.strip"] } :::
cleaned{|  make   your   robots   behave   |}
verbatim(|  make   your   robots   behave   |)
__main__:
	printf 'cleaned=[%s]\n' '${cleaned}'
	printf 'verbatim=[%s]\n' '${verbatim}'
"""


def test_brace_bracket_treatment_strips(tmp_path):
  # The `{| |}` body is piped through the pragma's treatment (stream.strip) at compile time,
  # so its runs of interior whitespace collapse to single spaces.
  r, out = _run(STRIP_PROG, tmp_path)
  assert r.returncode == 0, out
  assert "cleaned=[make your robots behave]" in out, out


def test_raw_paren_bracket_keeps_spacing(tmp_path):
  # The raw `(| |)` block carries no treatment, so its interior spacing survives verbatim --
  # the direct contrast to the treated brace block above.
  _, out = _run(STRIP_PROG, tmp_path)
  assert "verbatim=[make   your   robots   behave]" in out, out


def test_multiline_brace_body_is_treated(tmp_path):
  # A multi-line brace body is fed to the treatment whole; stream.strip drops the framing
  # newlines/indent and collapses the interior, yielding one clean value.
  src = r"""# cmk_pragma ::: { "block_brackets": ["{}=stream.strip"] } :::
title{|
   Robot     Wranglers
|}
__main__:
	printf 'title=[%s]\n' '${title}'
"""
  r, out = _run(src, tmp_path)
  assert r.returncode == 0, out
  assert "title=[Robot Wranglers]" in out, out


def test_unassigned_brace_slot_is_inert(tmp_path):
  # With NO block_brackets pragma the brace slot has no treatment, so a `{| |}` body is kept
  # verbatim (an open slot means nothing until you assign one) -- no compile error.
  src = r"""
slot{|  a   b   c  |}
__main__:
	printf 'slot=[%s]\n' '${slot}'
"""
  r, out = _run(src, tmp_path)
  assert r.returncode == 0, out
  assert "slot=[a   b   c]" in out, out


def test_treatment_is_configurable(tmp_path):
  # The treatment is whatever the pragma names -- not hardcoded to strip.  Point the slot at a
  # different stdin->stdout verb (stream.nl.to.space) and the same brace body transforms
  # differently: each source line folds onto one space-joined line.
  src = r"""# cmk_pragma ::: { "block_brackets": ["{}=stream.nl.to.space"] } :::
joined{|
one
two
three
|}
__main__:
	printf 'joined=[%s]\n' '${joined}'
"""
  r, out = _run(src, tmp_path)
  assert r.returncode == 0, out
  assert "joined=[one two three]" in out, out
