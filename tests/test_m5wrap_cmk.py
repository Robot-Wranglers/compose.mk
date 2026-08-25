"""Spec for the `.awk.cmk.m5wrap` compiler stage.

Source writes the bare `m5[1]`; the stage wraps it to `$(m5[1])`, which is
what makes the m5 accessors native to cmk-lang. The trigger is the three
characters `m5[` and nothing else, since a `[` after `m5` is unambiguous.
Dotted reads like `m5.tok.lparen` are out of scope by design and still need
an explicit `$(..)`. Asserts on fully-compiled `mk.compile` output.
"""

import pytest

pytestmark = pytest.mark.compiler

SQ = "'''"  # literal triple-quote


def _assign(ir, rhs):
  """Compile `v = <rhs>` and return the compiled line."""
  out = ir(f"v = {rhs}\n").stdout
  for line in out.splitlines():
    if line.startswith("v = "):
      return line
  raise AssertionError(f"no `v = ` line in compile output:\n{out}")


# --- wrapped: the accessor vocabulary --------------------------------------


@pytest.mark.parametrize(
  "src,want",
  [
    ("m5[1]", "$(m5[1])"),
    ("m5[9]", "$(m5[9])"),
    ("m5[2]?", "$(m5[2]?)"),
    ("m5[1][2]", "$(m5[1][2])"),
    ("m5[1][def]", "$(m5[1][def])"),
    ("m5[1][namespace]", "$(m5[1][namespace])"),
    ("m5[1][file]", "$(m5[1][file])"),
    ("m5[__self__]", "$(m5[__self__])"),
    ("m5[dollar]", "$(m5[dollar])"),
    ("m5[space]", "$(m5[space])"),
    ("m5[nl]", "$(m5[nl])"),
  ],
)
def test_wraps(ir, src, want):
  assert _assign(ir, src) == f"v = {want}"


@pytest.mark.parametrize("acc", ["len", "first", "last", "rest"])
def test_wraps_dot_accessor(ir, acc):
  """A trailing dot-accessor in `m5.__acc__` is pulled inside the wrap."""
  assert _assign(ir, f"m5[1].{acc}") == f"v = $(m5[1].{acc})"


def test_unknown_dot_accessor_stays_outside(ir):
  """An accessor absent from `m5.__acc__` is not swallowed by the wrap."""
  assert _assign(ir, "m5[1].gensym") == "v = $(m5[1]).gensym"


# --- wrapped: in position --------------------------------------------------


def test_wraps_inside_a_make_call(ir):
  assert _assign(ir, "$(subst x,y,m5[1])") == "v = $(subst x,y,$(m5[1]))"


def test_wraps_several_on_one_line(ir):
  got = _assign(ir, "hello, m5[1]$(if m5[2]?, and m5[2]?,)")
  assert got == "v = hello, $(m5[1])$(if $(m5[2]?), and $(m5[2]?),)"


def test_wraps_in_a_recipe(ir):
  out = ir("x:\n\techo m5[1]\n").stdout
  assert "echo $(m5[1])" in out


# --- skipped: already wrapped (idempotence) --------------------------------


@pytest.mark.parametrize("src", ["$(m5[1])", "${m5[1]}"])
def test_already_wrapped_is_left_alone(ir, src):
  """Re-running the stage over its own output is a no-op."""
  assert _assign(ir, src) == f"v = {src}"


# --- skipped: glued to a preceding name character --------------------------


@pytest.mark.parametrize("src", ["foo.m5[1]", "xm5[1]", "a1m5[1]"])
def test_name_prefixed_is_not_a_read(ir, src):
  """`m5[` is an accessor only when it starts a name."""
  assert _assign(ir, src) == f"v = {src}"


# --- skipped: dotted reads are out of scope --------------------------------


@pytest.mark.parametrize("src", ["m5.tok.lparen", "m5.__splat__", "m5.self"])
def test_dotted_reads_are_not_wrapped(ir, src):
  """Only the bracket form is unambiguous enough to auto-wrap."""
  assert _assign(ir, src) == f"v = {src}"


# --- skipped: the inert contexts -------------------------------------------


def test_inert_in_a_triple_quote_literal(ir):
  out = ir(f"v = {SQ}echo m5[1]{SQ}\n").stdout
  assert "m5[1]" in out
  assert "$(m5[1])" not in out


def test_inert_in_a_define_body(ir):
  out = ir("define d\necho m5[1]\nendef\n").stdout
  assert "echo m5[1]" in out
  assert "$(m5[1])" not in out


def test_inert_in_a_banana_body(ir):
  """A banana body lowers to a `define`; its contents stay verbatim."""
  out = ir("d(|\n\techo m5[1]\n|)\n").stdout
  assert "define d" in out
  assert "echo m5[1]" in out
  assert "$(m5[1])" not in out
