"""Tests for the unified `.awk.callform` + `.awk.tagged` stages (the phase-1
"grand unification" of call syntax).

The unification collapsed the old `.awk.callable` (target paren-as-stream + tagged)
and `.awk.macrocall` (`cmk.NAME[BODY]`) stages into ONE `.awk.callform` over both
call-anchors, with `.awk.tagged` split out ahead of it.  This file is the spec for
the macro anchor, the combined `(args)`/`[stream]` orders, the glyph streams, and
the not-yet-supported nested forms (xfailed below); the target-anchor edge cases
(backtick, not-a-call, bare-`this.`) live with the other stages in
`test_compiler_cmk.py`.

The unified grammar, for BOTH anchors `cmk.` (macro) and `${make} ` (target, the
post-dialect form of `this.`):

    (args)   = arguments      [stream] = stdin       combinable in EITHER order

Per-anchor the ONLY difference is the emitted call:
    cmk.NAME(a,b)[S] / cmk.NAME[S](a,b)  -> S | cmk.NAME(a,b)  (.awk.cmk.call finishes it)
    cmk.NAME[S]                          -> S | $(call NAME)
    cmk.NAME(a,b)   (no [...])           -> cmk.NAME(a,b) verbatim (call stage lowers it)
    ${make} NAME(a, b)[S] / [S](a, b)    -> S | ${make} NAME/a,b   (args WS-STRIPPED)
    ${make} NAME[S]                      -> S | ${make} NAME
    ${make} NAME(a, b)   (no [...])      -> ${make} NAME/a,b
    ${make} NAME'''L'''  (tagged)        -> '''L''' | ${make} NAME

DROPPED vs the old grammar: `target(stream)` no longer means "pipe stream"; a
target's `(...)` is ALWAYS arguments now (see test_drop_target_paren_is_args).

Happy paths assert the FULLY-compiled `mk.compile` output (so the triple-quote /
blockref / call stages downstream are exercised too); error + stage-isolation
cases drive the standalone `lang.comp.pipeline.callform` target so the nonzero exit and
the verbatim-passthrough are observable.
"""

import pytest

pytestmark = pytest.mark.compiler

TQ = '"""'  # interpolating triple-quote
SQ = "'''"  # literal triple-quote


def _recipe(ir, body):
  """Compile `x:; <body>` and return the recipe line (sans leading tab)."""
  r = ir(f"x:\n\t{body}\n")
  return r


# --- TARGET anchor: (args) lowers to /args ---------------------------------


def test_target_bare_paren_is_args(ir):
  r = _recipe(ir, "this.foo(a,b)")
  assert "${make} foo/a,b" in r.stdout


def test_target_args_whitespace_stripped(ir):
  # STRIP_WS applies to args only.
  r = _recipe(ir, "this.foo( a , b )")
  assert "${make} foo/a,b" in r.stdout


def test_target_paren_then_bracket(ir):
  r = _recipe(ir, f"this.foo(a,b)[{TQ}S{TQ}]")
  assert "printf '%s' \"S\" | ${make} foo/a,b" in r.stdout


def test_target_bracket_then_paren(ir):
  # swapped order -- identical lowering.
  r = _recipe(ir, f"this.foo[{TQ}S{TQ}](a,b)")
  assert "printf '%s' \"S\" | ${make} foo/a,b" in r.stdout


def test_target_bracket_only(ir):
  r = _recipe(ir, f"this.foo[{TQ}S{TQ}]")
  assert "printf '%s' \"S\" | ${make} foo" in r.stdout


def test_target_glyph_stream(ir):
  # a bare ⬦ref can't be a pipe LHS -> `cat ` prefixed before blockref lowers it.
  r = ir("define d\nhi\nendef\nx:\n\tthis.foo[⬦d]\n")
  assert "cat <($(call _mk.def.to.fd, d)) | ${make} foo" in r.stdout


# --- TARGET anchor: tagged form (.awk.tagged, runs before callform) --------


def test_target_tagged_literal(ir):
  r = _recipe(ir, f"this.foo{SQ}L{SQ}")
  assert "printf '%s' 'L' | ${make} foo" in r.stdout


def test_target_tagged_interpolating(ir):
  r = _recipe(ir, f"this.foo{TQ}${{V}}{TQ}")
  assert "printf '%s' \"${V}\" | ${make} foo" in r.stdout


# --- TARGET anchor: the DROPPED paren-as-stream form -----------------------


def test_drop_target_paren_is_args(ir):
  # OLD grammar: `target(stream)` piped the stream.  NEW: `(...)` is ALWAYS args,
  # so the triple-quote inside is just part of the (later-lowered) arg text.
  r = _recipe(ir, f"this.foo({TQ}S{TQ})")
  assert "${make} foo/" in r.stdout
  # it did NOT become a `... | ${make} foo` pipe.
  assert "| ${make} foo" not in r.stdout


# --- MACRO anchor ----------------------------------------------------------


def test_macro_bare_paren_verbatim_to_call(ir):
  # callform leaves `cmk.NAME(args)` verbatim; the late .awk.cmk.call lowers it.
  r = _recipe(ir, "cmk.foo(a,b)")
  assert "$(call foo,a,b)" in r.stdout


def test_macro_paren_then_bracket(ir):
  r = _recipe(ir, f"cmk.foo(a,b)[{TQ}S{TQ}]")
  assert "printf '%s' \"S\" | $(call foo,a,b)" in r.stdout


def test_macro_bracket_then_paren(ir):
  # swapped order -- identical lowering.
  r = _recipe(ir, f"cmk.foo[{TQ}S{TQ}](a,b)")
  assert "printf '%s' \"S\" | $(call foo,a,b)" in r.stdout


def test_macro_bracket_only(ir):
  r = _recipe(ir, f"cmk.foo[{TQ}S{TQ}]")
  assert "printf '%s' \"S\" | $(call foo)" in r.stdout


def test_macro_literal_single_line(ir):
  r = _recipe(ir, f"cmk.foo[{SQ}1 2 3 4{SQ}]")
  assert "printf '%s' '1 2 3 4' | $(call foo)" in r.stdout


def test_macro_args_may_contain_brackets(ir):
  # (args) is balanced-paren scanned, so `[`/`]` inside it are ordinary chars.
  r = _recipe(ir, f"cmk.f(x[0],y)[{TQ}B{TQ}]")
  assert "printf '%s' \"B\" | $(call f,x[0],y)" in r.stdout


def test_macro_glyph_stream(ir):
  r = ir("define d\nhi\nendef\nx:\n\tcmk.h[⬦d]\n")
  assert "cat <($(call _mk.def.to.fd, d)) | $(call h)" in r.stdout


# predicate and bang suffixes on a callform name; a trailing open-paren keeps them distinct from the conditional and shell assignment operators.


def test_macro_predicate_question_suffix(ir):
  r = _recipe(ir, "cmk.m5.defined?(HOME)")
  assert "$(call m5.defined?,HOME)" in r.stdout


def test_macro_bang_suffix(ir):
  r = _recipe(ir, "cmk.grow!(seed)")
  assert "$(call grow!,seed)" in r.stdout


def test_macro_predicate_dotted_name(ir):
  r = _recipe(ir, "cmk.kn.is.zero?(0)")
  assert "$(call kn.is.zero?,0)" in r.stdout


def test_macro_question_assign_is_not_a_call(ir):
  # a conditional-assign has no trailing paren, so the line stays verbatim.
  r = _recipe(ir, "cmk.foo?=bar")
  assert "$(call" not in r.stdout


def test_macro_bang_assign_is_not_a_call(ir):
  # a shell-assign disambiguates the same way.
  r = _recipe(ir, "cmk.foo!=bar")
  assert "$(call" not in r.stdout


def test_macro_glyph_file_stream(ir):
  # filled diamond ⬥ -> a real local file (not a stream FD).
  r = ir("define d\nhi\nendef\nx:\n\tcmk.h[⬥d]\n")
  assert "cat $(call _mk.def.tmpfile, d) | $(call h)" in r.stdout


def test_macro_unquoted_target_body(ir):
  # a `this.X` stream body: dialect lowers it to ${make} X before callform pipes it.
  r = _recipe(ir, "cmk.h[this.t]")
  assert "${make} t | $(call h)" in r.stdout


def test_macro_unquoted_non_command_not_a_compile_error(ir):
  # `[1 2 3 4]` lowers verbatim -- a runtime error if 1 isn't a command, NOT a
  # compile error (callform doesn't validate the stream's shell semantics).
  r = _recipe(ir, "cmk.h[1 2 3 4]")
  assert "1 2 3 4 | $(call h)" in r.stdout


# --- multiline literal: `]` may sit on its own line ------------------------


def test_macro_multiline_bracket_on_own_line(ir):
  r = ir(f"x:\n\tcmk.h[{SQ}L1\nL2{SQ}\n]\n")
  assert "printf '%s\\n%s' 'L1' 'L2' | $(call h)" in r.stdout


# --- multiple anchors on one line ------------------------------------------


def test_two_macros_one_line(ir):
  r = _recipe(ir, f"cmk.a(p)[{TQ}S{TQ}] cmk.b(q)")
  assert "printf '%s' \"S\" | $(call a,p) $(call b,q)" in r.stdout


# --- soft-keyword opt-out: a space after NAME -------------------------------


def test_target_space_opts_out_of_callform(ir):
  # `this.foo (a,b)` -- the space means foo is a bare target ref, not a call.
  r = _recipe(ir, "this.foo (a,b)")
  assert "${make} foo (a,b)" in r.stdout


# --- define-block inertness ------------------------------------------------


def test_inert_inside_define(ir):
  r = ir(f"define blk\ncmk.h[{SQ}x{SQ}]\nendef\n")
  assert f"cmk.h[{SQ}x{SQ}]" in r.stdout


def test_tagged_inert_inside_define(ir):
  r = ir(f"define blk\nthis.foo{SQ}L{SQ}\nendef\n")
  # dialect still lowers this.->${make}, but tagged must NOT pipe it.
  assert "| ${make} foo" not in r.stdout


# --- container-dispatch carve-out: callform leaves `.dispatch` verbatim -----


def test_dispatch_left_verbatim_by_callform(cmk):
  # A `*.dispatch` target's `(...)`/`[...]` is handled by a later stage, not here.
  r = cmk("lang.comp.pipeline.callform", stdin="x:\n\t${make} foo.dispatch(a,b)\n")
  assert r.ok, r.stderr
  assert "${make} foo.dispatch(a,b)" in r.stdout


# --- error cases (stage-isolated so the nonzero exit is observable) ---------
# These drive the standalone `lang.comp.pipeline.callform` target, so the macro anchor is the
# post-dialect sentinel `؆` (the dialect that rewrites `cmk.`->`؆` does not run on this isolated
# stage); the full pipeline still accepts `cmk.h[...]` as usual.
SENT = "؆"


def test_error_unterminated_unquoted_stream(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin=f"x:\n\t{SENT}h[a b\n")
  assert not r.ok
  assert "compose.mk (cmk:callform) error:" in r.stderr
  assert "unterminated" in r.stderr


def test_error_mixed_content_after_literal(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin=f"x:\n\t{SENT}h[{SQ}a{SQ} more]\n")
  assert not r.ok
  assert "expected ']'" in r.stderr


def test_error_unterminated_literal(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin=f"x:\n\t{SENT}h[{SQ}oops\n")
  assert not r.ok
  assert "unterminated triple-quoted literal" in r.stderr


# --- nested callform streams (parse_body recurses through `lower`) -----------
# A `[stream]` whose stream is ITSELF a callform composes left-to-right into a
# single pipeline: `this.a[this.b[this.c]]` == `${make} c | ${make} b | ${make} a`.
# parse_body recurses into the (unquoted, non-glyph) bracket body, so this works to
# arbitrary depth and across both anchors -- but a LITERAL body is never recursed,
# so its interior stays opaque (see test_nested_preserves_inner_literal).


def test_nested_target_three_levels(ir):
  r = _recipe(ir, "this.a[this.b[this.c]]")
  assert "${make} c | ${make} b | ${make} a" in r.stdout


def test_nested_target_four_levels(ir):
  r = _recipe(ir, "this.a[this.b[this.c[this.d]]]")
  assert "${make} d | ${make} c | ${make} b | ${make} a" in r.stdout


def test_nested_macro_outer_target_inner(ir):
  # outer macro `a` consumes the inner target pipeline as its stdin.
  r = _recipe(ir, "cmk.a[this.b[this.c]]")
  assert "${make} c | ${make} b | $(call a)" in r.stdout


def test_nested_target_outer_macro_stream_inner(ir):
  # inner macro `b` consumes target `c` as its stream, all inside target `a`'s stream.
  r = _recipe(ir, "this.a[cmk.b[this.c]]")
  assert "${make} c | $(call b) | ${make} a" in r.stdout


def test_nested_with_outer_args(ir):
  # the outer target carries (args) AND a nested stream -- both must survive.
  r = _recipe(ir, "this.a(p)[this.b[this.c]]")
  assert "${make} c | ${make} b | ${make} a/p" in r.stdout


def test_nested_glyph_inner(cmk):
  # a block-ref glyph at the bottom of a nested stream still cat-prefixes correctly.
  r = cmk(
    "mk.compile", stdin="define d\nhi\nendef\nx:\n\tthis.a[this.b[⬦d]]\n"
  )
  assert r.ok, r.stderr
  assert "cat <($(call _mk.def.to.fd, d)) | ${make} b | ${make} a" in r.stdout


def test_nested_preserves_inner_literal(ir):
  # LITERAL bodies are not recursed -- the literal `z` is lowered by triplequote,
  # NOT re-scanned for call-forms (literal immunity survives the recursion).
  r = _recipe(ir, 'this.a[cmk.b["""z"""]]')
  assert "printf '%s' \"z\" | $(call b) | ${make} a" in r.stdout


# --- `{env}` channel: an env-prefix, the dual of `[stream]`'s pipe-prefix ----
# `{k=v}` -> `k=v <lowered command>`, uniform for macros and targets, order-free
# with `(args)`/`[stream]`, assembled as `STREAM | ENV command`.  The value is passed
# RAW (the grammar's convention for every kwarg) so the shell resolves quoting and
# $-expansion; the compiler adds no quoting.  Distinct bracket from `(`/`[`, and `{`
# after a name/`)`/`]` is never a `${..}` ref -- so no collision.


def test_env_macro(ir):
  r = _recipe(ir, "cmk.f(a,b){e=v}")
  assert "e=v $(call f,a,b)" in r.stdout


def test_env_target(ir):
  r = _recipe(ir, "this.f(a,b){e=v}")
  assert "e=v ${make} f/a,b" in r.stdout


def test_env_bare_macro(ir):
  r = _recipe(ir, "cmk.f{e=v}")
  assert "e=v $(call f)" in r.stdout


def test_env_multi_var(ir):
  r = _recipe(ir, "cmk.f{a=1 b=2}")
  assert "a=1 b=2 $(call f)" in r.stdout


def test_env_shell_var_expands(ir):
  # a `$`-value passes through raw (`$$` = one runtime `$`), so the shell EXPANDS it at
  # dispatch -- not frozen to a literal.  This is why {env} can carry a recipe's own var.
  r = _recipe(ir, "cmk.f{CMK_X=$$payload}")
  assert "CMK_X=$$payload $(call f)" in r.stdout


def test_env_quoted_spaced_value(ir):
  # a quoted value with spaces survives whole: the `{..}` group is grabbed by brace depth,
  # then passed raw, so the user's quotes reach the shell (which strips them at runtime).
  r = _recipe(ir, 'cmk.f{msg="hello world" n=2}')
  assert 'msg="hello world" n=2 $(call f)' in r.stdout


def test_env_with_stream(ir):
  r = _recipe(ir, f"cmk.f(a,b){{e=v}}[{TQ}S{TQ}]")
  assert "printf '%s' \"S\" | e=v $(call f,a,b)" in r.stdout


def test_env_order_free_with_stream(ir):
  # `[S]{e}` == `{e}[S]` -- assembled as STREAM | ENV command regardless of order.
  a = _recipe(ir, f"cmk.f(a,b){{e=v}}[{TQ}S{TQ}]")
  b = _recipe(ir, f"cmk.f(a,b)[{TQ}S{TQ}]{{e=v}}")
  assert a.stdout.strip() == b.stdout.strip()


def test_env_no_collision_with_make_ref(ir):
  # `cmk.f${VAR}` -- the name scan stops at `$`, so `${VAR}` is NOT read as `{env}`.
  r = _recipe(ir, "cmk.f${VAR}")
  assert r.ok, r.stderr
  assert "${VAR}" in r.stdout  # the make ref survives verbatim
  assert "='" not in r.stdout  # ...and NO env prefix was mistakenly produced


def test_env_module_scope_warns_not_errors(ir):
  # a bare column-0 callform is module scope (no recipe to prefix) -- so `{env}` warns +
  # drops, never errors.
  r = ir("cmk.f{e=v}\n")
  assert "{env} at module scope" in r.stderr
  assert "$(call f)" in r.stdout and "e=v" not in r.stdout


def test_env_in_assignment_value_is_kept(ir):
  # a make-variable value runs in a recipe when expanded, so `{env}` inside an assignment is
  # recipe-scoped: kept, no warning (e.g. a macro whose body is a shell snippet).
  r = ir("MOD := cmk.f{e=v}\n")
  assert "{env} at module scope" not in r.stderr
  assert "MOD := e=v $(call f)" in r.stdout
