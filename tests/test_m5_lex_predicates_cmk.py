"""Unit contract for the `m5.lex` token-shape predicates (compose.mk).

`m5.lex.kwarg?`, `m5.lex.glob?` and `m5.lex.quoted?` answer "what shape is
this token" over a raw string. Non-empty is true, like the origin predicates,
and the returned text is the matched character rather than a boolean. The
probe binds each argument to a make variable first, which is how real callers
reach these: `$(call)` splits on commas in the makefile text.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")
_LINE = re.compile(r"^cmkprobe\[(.*)\]$", re.M)


def _probe(tmp_path, assigns, expr):
  """Expand `expr` after binding `assigns`, reporting through `$(info)`."""
  binds = "".join(f"{k} := {v}\n" for k, v in assigns.items())
  mk = tmp_path / "probe.mk"
  mk.write_text(
    f"include {COMPOSE}\n{binds}$(info cmkprobe[{expr}])\nprobe:;@true\n"
  )
  r = subprocess.run(
    ["make", "-s", "-f", str(mk), "probe"],
    capture_output=True,
    text=True,
    cwd=REPO,
    timeout=120,
  )
  assert r.returncode == 0, r.stderr
  hit = _LINE.search(_ANSI.sub("", r.stdout))
  assert hit, f"no probe line in:\n{r.stdout}"
  return hit.group(1)


def _call(tmp_path, pred, arg):
  return _probe(tmp_path, {"A": arg}, f"$(call {pred},$(A))")


# --- hits return the matched character, not a boolean ----------------------


@pytest.mark.parametrize(
  "pred,arg,want",
  [
    ("m5.lex.kwarg?", "def=foo", "="),
    ("m5.lex.glob?", "under*", "*"),
    ("m5.lex.glob?", "under?", "?"),
    ("m5.lex.quoted?", 'a="b"', '"'),
    ("m5.lex.quoted?", "a='b'", "'"),
  ],
)
def test_hit(tmp_path, pred, arg, want):
  assert _call(tmp_path, pred, arg) == want


# --- misses are empty ------------------------------------------------------


@pytest.mark.parametrize(
  "pred,arg",
  [
    ("m5.lex.kwarg?", "plainword"),
    ("m5.lex.glob?", "plainword"),
    ("m5.lex.quoted?", "plainword"),
  ],
)
def test_miss(tmp_path, pred, arg):
  assert _call(tmp_path, pred, arg) == ""


@pytest.mark.parametrize(
  "pred", ["m5.lex.kwarg?", "m5.lex.glob?", "m5.lex.quoted?"]
)
def test_empty_input_is_a_miss(tmp_path, pred):
  assert _probe(tmp_path, {}, f"$(call {pred},)") == ""


# --- each predicate is an or over its character set ------------------------


def test_glob_both_wildcards_concatenates(tmp_path):
  """Both present means both matches concatenate; still just truthy."""
  assert _call(tmp_path, "m5.lex.glob?", "a*b?c") == "*?"


def test_quoted_both_quote_styles_concatenates(tmp_path):
  assert _call(tmp_path, "m5.lex.quoted?", "\"a\" 'b'") == "\"'"


# --- a bound argument reaches the predicate whole --------------------------


def test_embedded_comma_does_not_truncate(tmp_path):
  """The interesting char sits past a comma, so a re-split would miss it."""
  assert _call(tmp_path, "m5.lex.quoted?", 'bases=A,B name="q"') == '"'
  assert _call(tmp_path, "m5.lex.glob?", "defs=a,b*c") == "*"


# --- the adopting caller still behaves -------------------------------------


def test_ctx_reads_a_comma_bearing_value(tmp_path):
  """`m5.ctx?` routes its quote test through the predicate."""
  got = _probe(
    tmp_path, {"V": 'bases=A,B name="q"'}, "$(call m5.ctx?,$(V),bases)"
  )
  assert got == "A,B"


def test_ctx_reads_a_quoted_value(tmp_path):
  got = _probe(
    tmp_path, {"V": 'bases=A,B name="q"'}, "$(call m5.ctx?,$(V),name)"
  )
  assert got == "q"
