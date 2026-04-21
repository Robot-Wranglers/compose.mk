"""Tests for FLUENT-STYLE method-chaining (`a().b().c()`), folded into the
`.awk.cmk.receivers` stage.

A call-close `)`/`]`/`}` immediately followed by `.<receiver>(` is a chain
JUNCTION: the `.` is rewritten to a ` | ` shell-pipe boundary and the right
operand routes as a fresh smart send.  Chaining is therefore delegated to the one
receiver router -- it composes every receiver kind, and there is no per-form
chaining code (see `test_receivers_cmk.py` for the send-forms themselves).

The junction is deliberately narrow, so ordinary dotted names are never touched:
it fires ONLY when the `.` directly follows a call-close AND the name after it is a
registered receiver AND a call-suffix follows.  A bare `$(date).log`, or a dotted
path on a NON-receiver, both pass through verbatim.

These pin the FULLY-compiled `mk.compile` output.
"""

import pytest

pytestmark = pytest.mark.compiler

# Register three receivers with no macro twin (channels route smart -> ${make}).
DECL = (
  "channel alpha(| |)\n"
  "channel beta(| |)\n"
  "channel gamma(| |)\n"
)


def smart(name, macro_args="", target_stem="", paren=False):
  """The smart-routing core the receiver stage emits for a `(`/`[`/`{` send.
  Wraps a `.__call__` arm (the callable-dunder protocol) around the origin-routing core.
  A no-arg paren callform (`x()`) guards its macro branch with the namespace-not-callable fault."""
  if macro_args:
    mb = f"$(call {name},{macro_args})"
  elif paren:
    mb = (
      f"$(if $(filter-out undefined,$(origin {name}.__name__)),"
      f"$(error cmk-fault errno=GRAMMAR code=65 :: cmk: {name}() is not callable: "
      f"{name} is a namespace with no .__call__ -- call a member like {name}.x or "
      f"define .__call__),$(call {name}))"
    )
  else:
    mb = f"$(call {name})"
  tb = f"${{make}} {name}/{target_stem}" if target_stem else f"${{make}} {name}"
  inner = f"$(if $(filter file override,$(origin {name})),{mb},{tb})"
  cb = f"$(call {name}.__call__,{macro_args})" if macro_args else f"$(call {name}.__call__)"
  return f"$(if $(filter file override,$(origin {name}.__call__)),{cb},{inner})"


def _c(ir, body, decl=DECL):
  return ir(body, decl=decl, wrap=True)


# --- the junction inserts a pipe between sends -------------------------------


def test_two_link_chain(ir):
  # `alpha().beta()` -> the two smart sends joined by a shell pipe.
  r = _c(ir, "alpha().beta()")
  assert f"{smart('alpha', paren=True)} | {smart('beta', paren=True)}" in r.stdout


def test_three_link_chain(ir):
  r = _c(ir, "alpha().beta().gamma()")
  assert f"{smart('alpha', paren=True)} | {smart('beta', paren=True)} | {smart('gamma', paren=True)}" in r.stdout


def test_args_ride_along(ir):
  # each link keeps its own `(args)`.
  r = _c(ir, "alpha(a).beta(b)")
  assert f"{smart('alpha', 'a', 'a')} | {smart('beta', 'b', 'b')}" in r.stdout


def test_stream_close_is_a_junction(ir):
  # a `[stream]` close (`]`) is a junction just like a `)` close.
  r = _c(ir, 'alpha["""hi"""].beta()')
  assert " | " + smart("beta", paren=True) in r.stdout


def test_right_operand_may_be_dotted(ir):
  # the right operand routes as an ordinary dotted send -- `beta.method`.
  r = _c(ir, "alpha().beta.method()")
  assert f"{smart('alpha', paren=True)} | {smart('beta.method', paren=True)}" in r.stdout


# --- the junction is narrow: it does not over-fire ---------------------------


def test_non_receiver_dotted_path_untouched(ir):
  # `alpha` IS a receiver, but `nope.alpha(` is a dotted path on non-receiver
  # `nope` (the `.` does not follow a CALL-CLOSE), so nothing is rewritten.
  r = _c(ir, "nope.alpha()")
  assert "nope.alpha()" in r.stdout
  assert " | " not in r.stdout


def test_make_expansion_dot_not_a_junction(ir):
  # `$(date).log` -- the name after the `)` close (`log`) is not a receiver, so
  # the `.` is left alone (no false pipe on ordinary shell/make text).
  r = _c(ir, "echo $(date).log")
  assert "echo $(date).log" in r.stdout
  assert " | " not in r.stdout


# --- multi-line chains: leading-dot continuations fold to one line -----------


def _ml(ir, body, decl=DECL):
  """Compile a target whose recipe `body` may span several indented lines."""
  r = ir(f"{decl}x:\n{body}\n")
  return r


def test_multiline_uniform_indent(ir):
  # continuations at the SAME indent as the producer fold + chain.
  r = _ml(ir, "  alpha()\n  .beta()\n  .gamma()")
  assert f"{smart('alpha', paren=True)} | {smart('beta', paren=True)} | {smart('gamma', paren=True)}" in r.stdout


def test_multiline_deeper_indent(ir):
  # continuations aligned DEEPER (the idiomatic look) also fold -- and folding
  # before `indent` sidesteps the inconsistent-indentation error that used to
  # silently drop the line.
  r = _ml(ir, "  alpha()\n    .beta()\n    .gamma()")
  assert f"{smart('alpha', paren=True)} | {smart('beta', paren=True)} | {smart('gamma', paren=True)}" in r.stdout


def test_multiline_matches_single_line(ir):
  # the multi-line form lowers identically to the one-line form.
  one = _c(ir, "alpha().beta()").stdout
  many = _ml(ir, "  alpha()\n  .beta()").stdout
  needle = f"{smart('alpha', paren=True)} | {smart('beta', paren=True)}"
  assert needle in one and needle in many


def test_blank_line_ends_the_chain(ir):
  # a blank line between links is NOT a continuation -- the second link is left
  # alone (no fold, no pipe joining the two).
  r = _ml(ir, "  alpha()\n\n  .beta()")
  assert f"{smart('alpha', paren=True)} | " not in r.stdout


def test_multiline_non_receiver_not_folded(ir):
  # a leading-dot line whose root is not a receiver stays a separate recipe line
  # (joined with `&&` by joinbody), never merged onto the previous.
  r = _ml(ir, "  echo hi\n  .nope()")
  assert ".nope()" in r.stdout
  assert " | " not in r.stdout


# --- end-to-end: a fluent chain actually pipes at runtime --------------------


def test_end_to_end_pipes(cmk, tmp_path):
  f = tmp_path / "chain.cmk"
  f.write_text(
    "emit(| printf 'a\\nb\\nc\\n' |)\n"
    "upper(| tr a-z A-Z |)\n"
    "count(| wc -l | tr -d ' ' |)\n"
    "__main__:; emit().upper().count()\n"
  )
  r = cmk("cmk", "run", str(f), env={"CMK_SUPERVISOR": "1"})
  assert r.ok, r.stderr
  assert "3" in r.stdout


def test_end_to_end_multiline_pipes(cmk, tmp_path):
  f = tmp_path / "chain_ml.cmk"
  f.write_text(
    "emit(| printf 'a\\nb\\nc\\n' |)\n"
    "upper(| tr a-z A-Z |)\n"
    "count(| wc -l | tr -d ' ' |)\n"
    "__main__:\n"
    "  emit()\n"
    "    .upper()\n"
    "    .count()\n"
  )
  r = cmk("cmk", "run", str(f), env={"CMK_SUPERVISOR": "1"})
  assert r.ok, r.stderr
  assert "3" in r.stdout
