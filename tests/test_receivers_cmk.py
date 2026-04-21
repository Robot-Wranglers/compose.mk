"""Tests for ANCHORLESS receiver sends (`.awk.cmk.receivers`).

A name registered as a "receiver" by a `declare.*`/`import` in the source needs no
`this.`/`cmk.` anchor: `NAME.method...` is recognized and an anchor is injected, after
which the tagged/callform stages lower it.  The receiver namespace is scanned
(`.cmk.scan.receivers`) from each declarable kind -- channel / module `namespace=`,
polyglot & single-image container `def=`, the banana callform-name, and the
`import <ns>` directive.

SMART ROUTING: an arg/stream/env send (`(`/`[`/`{`) lowers to the SMART core
`$(if $(filter file override,$(origin NAME)),$(call NAME,..),${make} NAME/..)` -- a
defined MACRO wins (fast, no reparse), else the published TARGET, decided at runtime.
The `/`-stem and adjacent triple-literal forms stay pure TARGET sends (path-stem /
heredoc-body shapes).  For a channel receiver like `inbox.*` no macro exists, so the
core routes to `${make}` at runtime -- behaviorally identical to the pre-smart target
dispatch, just expressed as the routing core.

These pin the FULLY-compiled `mk.compile` output: sends lower, while LHS target defs,
bare prereqs, non-receivers, and define-blocks are left untouched, and a legacy
`this.`/`cmk.`-anchored send does not double-anchor.
"""

import pytest

pytestmark = pytest.mark.compiler

DECL = "channel inbox(| |)\n"


def smart(name, macro_args="", target_stem=""):
  """The smart-routing core the receiver stage now emits for `(`/`[`/`{` sends.
  Wraps a `.__call__` arm (the callable-dunder protocol) around the origin-routing core:
  if `NAME.__call__` is defined, call it; else fall back to the macro/target routing."""
  mb = f"$(call {name},{macro_args})" if macro_args else f"$(call {name})"
  tb = (
    f"${{make}} {name}/{target_stem}" if target_stem else f"${{make}} {name}"
  )
  inner = f"$(if $(filter file override,$(origin {name})),{mb},{tb})"
  cb = (
    f"$(call {name}.__call__,{macro_args})" if macro_args else f"$(call {name}.__call__)"
  )
  return f"$(if $(filter file override,$(origin {name}.__call__)),{cb},{inner})"


def _c(ir, body, decl=DECL):
  return ir(body, decl=decl, wrap=True)


# --- the send-forms all lower (no anchor written by hand) --------------------


def test_bracket_stream(ir):
  # `[stream]` wraps the smart core (dispatch-agnostic pipe prefix).
  r = _c(ir, 'inbox.emit["""hi"""]')
  assert f"printf '%s' \"hi\" | {smart('inbox.emit')}" in r.stdout


def test_paren_args(ir):
  # `(args)` routes smart: macro branch keeps args verbatim, target branch a ws-stripped stem.
  r = _c(ir, "inbox.foo(a,b)")
  assert smart("inbox.foo", "a,b", "a,b") in r.stdout


def test_paren_then_stream(ir):
  r = _c(ir, 'inbox.foo(a,b)["""S"""]')
  assert f"printf '%s' \"S\" | {smart('inbox.foo', 'a,b', 'a,b')}" in r.stdout


def test_env_prefix(ir):
  # `{env}` is a runtime prefix that wraps the smart core (dual to the stream pipe).
  # The value passes RAW (no compiler quoting -- see test_callform_cmk.py).
  r = _c(ir, "inbox.bar{e=v}")
  assert f"e=v {smart('inbox.bar')}" in r.stdout


def test_slash_arg(ir):
  # the `/arg` parametric form stays a pure TARGET send (path-stem shape), NOT smart.
  r = _c(ir, "logins <- inbox.filter.field_equal/type,login")
  assert "logins=`${make} inbox.filter.field_equal/type,login`" in r.stdout
  assert "$(origin inbox.filter" not in r.stdout


def test_tagged_literal(ir):
  # adjacent triple-literal stays a pure TARGET send (heredoc-body shape), NOT smart.
  r = _c(ir, "inbox.emit'''L'''")
  assert "printf '%s' 'L' | ${make} inbox.emit" in r.stdout
  assert "$(origin inbox.emit" not in r.stdout


def test_glyph_stream(ir):
  r = ir(
    f"{DECL}define d\nhi\nendef\nx:\n\tinbox.emit[⬦d]\n",
  )
  assert f"cat <($(call _mk.def.to.fd, d)) | {smart('inbox.emit')}" in r.stdout


def test_deep_method_path(ir):
  # the method path may be multi-segment (`a.b.c`); the `/arg` form stays TARGET.
  r = _c(ir, "inbox.first.match.field_equal/id,x")
  assert "${make} inbox.first.match.field_equal/id,x" in r.stdout


# --- multiple receivers ------------------------------------------------------


def test_two_receivers(ir):
  decl = "channel inbox(| |)\nchannel fault(| |)\n"
  r = ir(
    f'{decl}x:\n\tinbox.emit["""a"""]\n\tfault.emit["""b"""]\n',
  )
  assert f"printf '%s' \"a\" | {smart('inbox.emit')}" in r.stdout
  assert f"printf '%s' \"b\" | {smart('fault.emit')}" in r.stdout


def test_two_paren_ctor_kwargs_still_registers(ir):
  # a construction with a leading kwargs paren (`channel inbox(match=..)(| |)`,
  # the declarative `match=`/`init_data=`/`at_exit=` sugar) still registers `inbox`
  # as a receiver: the scan skips the `(kwargs)` before the banana, so a later
  # `inbox.emit[...]` send lowers exactly like the bare `channel inbox(| |)` form.
  r = _c(
    ir,
    'inbox.emit["""hi"""]',
    decl="channel inbox(match='key=type value=login')(| |)\n",
  )
  assert f"printf '%s' \"hi\" | {smart('inbox.emit')}" in r.stdout


# --- things that must NOT be rewritten ---------------------------------------


def test_lhs_target_def_untouched(ir):
  # `inbox.seed:` is a target definition (suffix `:`), never a send.
  r = ir(f"{DECL}inbox.seed:\n\techo hi\n")
  assert "inbox.seed:" in r.stdout
  assert "${make} inbox.seed" not in r.stdout
  assert "$(origin inbox.seed" not in r.stdout


def test_bare_prereq_untouched(cmk):
  # a bare `inbox.x` (no call-suffix) stays a plain name (e.g. a prerequisite).
  r = cmk(
    "mk.compile", stdin=f"{DECL}__main__: inbox.seed\ninbox.seed:; @true\n"
  )
  assert r.ok, r.stderr
  assert "__main__: inbox.seed" in r.stdout
  assert "${make} inbox.seed" not in r.stdout


def test_undeclared_name_passthrough(ir):
  # no declare -> `foo.bar[...]` is not a receiver, so no anchor/routing is injected.
  r = ir(
    'x:\n\tfoo.bar["""z"""]\n',
  )
  assert "${make} foo.bar" not in r.stdout
  assert "$(origin foo.bar" not in r.stdout


def test_legacy_this_no_double_anchor(ir):
  # a `this.`-anchored send forces the TARGET path (dialect anchor, not a receiver) and
  # is NOT re-anchored to `${make} ${make}` nor turned into a smart core.
  r = _c(ir, 'this.inbox.emit["""hi"""]')
  assert "printf '%s' \"hi\" | ${make} inbox.emit" in r.stdout
  assert "${make} ${make}" not in r.stdout
  assert "$(origin inbox.emit" not in r.stdout


def test_macro_anchored_receiver_no_double_anchor(ir):
  # a `cmk.`-anchored receiver send keeps the MACRO path: the receivers stage's
  # `prev != "؆"` guard skips the dialect sentinel (`cmk.`->`؆`), so it lowers to
  # `$(call ...)` and is NOT also anchored/routed.
  r = _c(ir, 'cmk.inbox.emit["""hi"""]')
  assert "printf '%s' \"hi\" | $(call inbox.emit)" in r.stdout
  assert "${make} inbox.emit" not in r.stdout
  assert "$(origin inbox.emit" not in r.stdout


def test_inert_inside_define(cmk):
  r = cmk(
    "mk.compile", stdin=f'{DECL}define blk\ninbox.emit["""x"""]\nendef\n'
  )
  assert r.ok, r.stderr
  assert 'inbox.emit["""x"""]' in r.stdout
  assert "${make} inbox.emit" not in r.stdout
  assert "$(origin inbox.emit" not in r.stdout


def test_parametric_target_def_untouched(ir):
  # `inbox.scan/%:` is a parametric target DEFINITION -- the `/` is a pattern stem,
  # not a `/arg` send, so the rule's target spec must be left alone.
  r = ir(f"{DECL}inbox.scan/%:\n\t@echo ${{*}}\n")
  assert "inbox.scan/%:" in r.stdout
  assert "${make} inbox.scan" not in r.stdout


def test_oneliner_recipe_send_lowers(ir):
  # a send in the inline recipe of a `name:; ...` one-liner still lowers (the scan
  # starts after the rule's `;`).
  r = ir(f'{DECL}x:; inbox.emit["""hi"""]\n')
  assert f"printf '%s' \"hi\" | {smart('inbox.emit')}" in r.stdout


# --- other declare kinds: the scan is generic over the receiver namespace -----
# (mk.compile only transpiles, so these snippets need no real module/polyglot to
# exist -- same as the existing compose.import(file=x.yml) import tests.)


def test_module_namespace_send(ir):
  # a module's receiver is its `namespace=` value; sends to it lower anchorless.
  r = ir(
    '$(call import.module, def=M namespace=Mod)\nx:\n\tMod.run["""hi"""]\n',
  )
  assert f"printf '%s' \"hi\" | {smart('Mod.run')}" in r.stdout


def test_module_source_def_not_registered(ir):
  # `def=M` is the module SOURCE, not a receiver -- only `namespace=Mod` registers,
  # so `M.x[...]` must NOT be anchored.
  r = ir(
    '$(call import.module, def=M namespace=Mod)\nx:\n\tM.x["""a"""]\n',
  )
  assert "${make} M.x" not in r.stdout
  assert "$(origin M.x" not in r.stdout


def test_module_banana_and_namespace_register(ir):
  # a module is now a generic banana `M[| .. |]` (registers M, the banana name) imported by
  # `import.module(def=M namespace=Aliased)` (registers Aliased, the namespace= kwarg).  Both
  # names are receivers -- callable anchorless, no `this.` prefix.
  r = ir(
    'M[|\n  greet:; @true\n|]\n$(call import.module, def=M namespace=Aliased)\n'
    'x:\n\tM.run["""a"""]\n\tAliased.run["""hi"""]\n',
  )
  assert f"printf '%s' \"a\" | {smart('M.run')}" in r.stdout
  assert f"printf '%s' \"hi\" | {smart('Aliased.run')}" in r.stdout


def test_polyglot_def_registers(ir):
  # a polyglot's namespace defaults to its `def=` block name, so that registers.
  r = ir(
    '$(call code, def=poly bind=x)\ny:\n\tpoly.run["""z"""]\n',
  )
  assert f"printf '%s' \"z\" | {smart('poly.run')}" in r.stdout


def test_unbound_code_receiver_registers(ir):
  # `code.unbound NAME(| .. |)` (an unbound code-object) registers NAME as a receiver.
  r = ir(
    'code.unbound widget(|\nsome code\n|)\nz:\n\twidget.preview["""x"""]\n',
  )
  assert f"printf '%s' \"x\" | {smart('widget.preview')}" in r.stdout




def test_docker_import_def_registers(ir):
  # single-image `docker.import(def=Dockerfile.NAME)` registers NAME.
  r = ir(
    '$(call docker.import, def=Dockerfile.box)\nz:\n\tbox.shell["""hi"""]\n',
  )
  assert f"printf '%s' \"hi\" | {smart('box.shell')}" in r.stdout


def test_capture_lhs_registers(ir):
  # a `<-` capture binds its LHS name (`lang.rex.recv.capture`), which registers as a
  # receiver -- so a later `NAME.method...` send to it lowers anchorless (no
  # `this.`/`cmk.` prefix), exactly like a declared namespace.
  r = ir(
    'handle <- inbox.emit/x\nz:\n\thandle.run["""hi"""]\n',
  )
  assert f"printf '%s' \"hi\" | {smart('handle.run')}" in r.stdout


def test_plain_assign_not_registered(ir):
  # a plain `=` assignment is an ordinary make var, NOT a capture -- its LHS must
  # NOT register as a receiver (only `<-` does), else every make var would become
  # one.  So `thing.run[...]` stays a passthrough (no anchor/routing injected).
  r = ir(
    'thing = value\nz:\n\tthing.run["""x"""]\n',
  )
  assert "${make} thing.run" not in r.stdout
  assert "$(origin thing.run" not in r.stdout


def test_capture_binds_stdout(ir):
  # plain `NAME <- <send>` RUNS the RHS now and captures its stdout into the LHS
  # (module-level `:= $(shell ..)`), the one-shot value semantics.
  r = ir("v <- this.some/target\nz:; @true\n")
  assert "v := $(shell ${make} some/target)" in r.stdout


def test_handle_bind_stores_without_running(ir):
  # `&NAME <- <send>` is a HANDLE bind: the `&` marks a reference declaration, so the
  # already-lowered RHS is STORED as a callable macro (`NAME = ..`) rather than run
  # (no `$(shell ..)`/backticks).  The LHS still registers as a receiver, so `NAME()`
  # lowers -- calling the handle runs it later.
  r = ir("&h <- this.some/target\nz:\n\th()\n")
  assert "h = ${make} some/target" in r.stdout
  assert "h := $(shell" not in r.stdout
  assert "h=`" not in r.stdout
  # the handle is callable -- `h()` lowers via the receiver core (the `&` LHS registered `h`).
  assert "$(origin h))" in r.stdout or "$(call h)" in r.stdout


def test_copy_threads_new_name(ir):
  # `LHS <- <obj>.copy()` re-mints <obj> under the new name LHS: the capture stage rewrites it
  # to `$(call <obj>.copy, LHS)`, threading the name a blind RHS callform cannot reach.  (The
  # code-object mint provides `<obj>.copy` + the stashed `.__ctor_src__` it re-inits from.)
  r = ir("dupe <- orig.copy()\nz:; @true\n")
  assert "$(call orig.copy,dupe)" in r.stdout
  # the copy form does NOT fall through to the run+capture branches.
  assert "dupe := $(shell" not in r.stdout
  assert "dupe=`" not in r.stdout


def test_new_threads_instance_name(ir):
  # `LHS <- Class.new()` mints a fresh instance under the new name LHS: the capture stage
  # rewrites it to `$(call Class, LHS)` (a class is its own positional ctor, so LHS becomes
  # `self`), threading the name a blind RHS callform cannot reach -- sibling of `.copy()`.
  r = ir("alice <- Pet.new()\nz:; @true\n")
  assert "$(call Pet,alice)" in r.stdout
  # the new form does NOT fall through to the run+capture branches.
  assert "alice := $(shell" not in r.stdout
  assert "alice=`" not in r.stdout


def test_new_tolerates_trailing_comment(ir):
  # A trailing `# comment` must not defeat the mint: `.new()` does NOT route through
  # `$(shell ..)` (which would swallow a comment as a shell comment), so the branch has to
  # strip the comment itself rather than fall through to `alice := $(shell Pet.new() # ..)`
  # (which then runs `Pet.new()` as a shell command).  The demos write this form.
  r = ir("alice <- Pet.new()   # bind a named instance via <-\nz:; @true\n")
  assert "$(call Pet,alice)" in r.stdout
  assert "alice := $(shell" not in r.stdout
