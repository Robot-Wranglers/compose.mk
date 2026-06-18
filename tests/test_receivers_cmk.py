"""Tests for ANCHORLESS receiver sends (`.awk.cmk.receivers`).

A name registered as a "receiver" by a `declare.*` call in the source needs no
`this.`/`cmk.` anchor: `NAME.method...` is recognized as a target send and gets the
`${make} ` anchor injected, after which the existing tagged/callform stages lower it
exactly as for `this.`.  The receiver namespace is scanned (`.cmk.scan.receivers`)
from each declarable kind -- channel / module `namespace=` (or `⦕ as`), polyglot
& single-image container `def=`, and the `⟦`/`🞹`/`⫻` sugar blocks.  The stage runs
after dialect+sugar, before tagged; it fires ONLY for declared receivers, ONLY at a
word boundary, ONLY before a call-suffix (`(`/`[`/`/`/adjacent triple-quote).

These pin the FULLY-compiled `mk.compile` output: receiver sends lower, while LHS
target defs, bare prereqs, non-receivers, and define-blocks are left untouched, and a
legacy `this.`-anchored send does not double-anchor.
"""

import pytest

pytestmark = pytest.mark.compiler

DECL = "cmk.declare.channel(namespace=inbox)\n"


def _c(cmk, body, decl=DECL):
  r = cmk("mk.compile", stdin=f"{decl}x:\n\t{body}\n")
  assert r.ok, r.stderr
  return r


# --- the send-forms all lower (no anchor written by hand) --------------------


def test_bracket_stream(cmk):
  r = _c(cmk, 'inbox.emit["""hi"""]')
  assert "printf '%s' \"hi\" | ${make} inbox.emit" in r.stdout


def test_paren_args(cmk):
  r = _c(cmk, "inbox.foo(a,b)")
  assert "${make} inbox.foo/a,b" in r.stdout


def test_paren_then_stream(cmk):
  r = _c(cmk, 'inbox.foo(a,b)["""S"""]')
  assert "printf '%s' \"S\" | ${make} inbox.foo/a,b" in r.stdout


def test_slash_arg(cmk):
  # the `/arg` parametric form is a call-suffix too.
  r = _c(cmk, "logins ⇐ inbox.filter.field_equal/type,login")
  assert "logins=`${make} inbox.filter.field_equal/type,login`" in r.stdout


def test_tagged_literal(cmk):
  r = _c(cmk, "inbox.emit'''L'''")
  assert "printf '%s' 'L' | ${make} inbox.emit" in r.stdout


def test_glyph_stream(cmk):
  r = cmk(
    "mk.compile",
    stdin=f"{DECL}define d\nhi\nendef\nx:\n\tinbox.emit[⬦d]\n",
  )
  assert r.ok, r.stderr
  assert "cat <($(call _mk.def.to.fd, d)) | ${make} inbox.emit" in r.stdout


def test_deep_method_path(cmk):
  # the method path may be multi-segment (`a.b.c`); the whole `NAME.path` is the target.
  r = _c(cmk, "inbox.first.match.field_equal/id,x")
  assert "${make} inbox.first.match.field_equal/id,x" in r.stdout


# --- multiple receivers ------------------------------------------------------


def test_two_receivers(cmk):
  decl = "cmk.declare.channel(namespace=inbox)\ncmk.declare.channel(namespace=fault)\n"
  r = cmk(
    "mk.compile",
    stdin=f'{decl}x:\n\tinbox.emit["""a"""]\n\tfault.emit["""b"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"a\" | ${make} inbox.emit" in r.stdout
  assert "printf '%s' \"b\" | ${make} fault.emit" in r.stdout


# --- things that must NOT be rewritten ---------------------------------------


def test_lhs_target_def_untouched(cmk):
  # `inbox.seed:` is a target definition (suffix `:`), never a send.
  r = cmk("mk.compile", stdin=f"{DECL}inbox.seed:\n\techo hi\n")
  assert r.ok, r.stderr
  assert "inbox.seed:" in r.stdout
  assert "${make} inbox.seed" not in r.stdout


def test_bare_prereq_untouched(cmk):
  # a bare `inbox.x` (no call-suffix) stays a plain name (e.g. a prerequisite).
  r = cmk(
    "mk.compile", stdin=f"{DECL}__main__: inbox.seed\ninbox.seed:; @true\n"
  )
  assert r.ok, r.stderr
  assert "__main__: inbox.seed" in r.stdout
  assert "${make} inbox.seed" not in r.stdout


def test_undeclared_name_passthrough(cmk):
  # no declare -> `foo.bar[...]` is not a receiver, so no anchor is injected.
  r = cmk(
    "mk.compile",
    stdin='x:\n\tfoo.bar["""z"""]\n',
  )
  assert r.ok, r.stderr
  assert "${make} foo.bar" not in r.stdout


def test_legacy_this_no_double_anchor(cmk):
  # a `this.`-anchored send still works and is NOT re-anchored to `${make} ${make}`.
  r = _c(cmk, 'this.inbox.emit["""hi"""]')
  assert "printf '%s' \"hi\" | ${make} inbox.emit" in r.stdout
  assert "${make} ${make}" not in r.stdout


def test_macro_anchored_receiver_no_double_anchor(cmk):
  # a `cmk.`-anchored receiver send keeps the MACRO path: the receivers stage's
  # `prev != "؆"` guard skips the dialect sentinel (`cmk.`->`؆`), so it lowers to
  # `$(call ...)` and is NOT also `${make} `-anchored.
  r = _c(cmk, 'cmk.inbox.emit["""hi"""]')
  assert "printf '%s' \"hi\" | $(call inbox.emit)" in r.stdout
  assert "${make} inbox.emit" not in r.stdout


def test_inert_inside_define(cmk):
  r = cmk(
    "mk.compile", stdin=f'{DECL}define blk\ninbox.emit["""x"""]\nendef\n'
  )
  assert r.ok, r.stderr
  assert 'inbox.emit["""x"""]' in r.stdout
  assert "${make} inbox.emit" not in r.stdout


def test_parametric_target_def_untouched(cmk):
  # `inbox.scan/%:` is a parametric target DEFINITION -- the `/` is a pattern stem,
  # not a `/arg` send, so the rule's target spec must be left alone.
  r = cmk("mk.compile", stdin=f"{DECL}inbox.scan/%:\n\t@echo ${{*}}\n")
  assert r.ok, r.stderr
  assert "inbox.scan/%:" in r.stdout
  assert "${make} inbox.scan" not in r.stdout


def test_oneliner_recipe_send_lowers(cmk):
  # a send in the inline recipe of a `name:; ...` one-liner still lowers (the scan
  # starts after the rule's `;`).
  r = cmk("mk.compile", stdin=f'{DECL}x:; inbox.emit["""hi"""]\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"hi\" | ${make} inbox.emit" in r.stdout


# --- other declare kinds: the scan is generic over the receiver namespace -----
# (mk.compile only transpiles, so these snippets need no real module/polyglot to
# exist -- same as the existing compose.import(file=x.yml) import tests.)


def test_module_namespace_send(cmk):
  # a module's receiver is its `namespace=` value; sends to it lower anchorless.
  r = cmk(
    "mk.compile",
    stdin='$(call import.module, def=M namespace=Mod)\nx:\n\tMod.run["""hi"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"hi\" | ${make} Mod.run" in r.stdout


def test_module_source_def_not_registered(cmk):
  # `def=M` is the module SOURCE, not a receiver -- only `namespace=Mod` registers,
  # so `M.x[...]` must NOT be anchored.
  r = cmk(
    "mk.compile",
    stdin='$(call import.module, def=M namespace=Mod)\nx:\n\tM.x["""a"""]\n',
  )
  assert r.ok, r.stderr
  assert "${make} M.x" not in r.stdout


def test_module_sugar_as_clause_registers(cmk):
  # the `⦖ .. ⦕ as NAME` module sugar registers NAME as a receiver.
  r = cmk(
    "mk.compile",
    stdin='⦖ M\ngreet:; @true\n⦕ as Aliased\nx:\n\tAliased.run["""hi"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"hi\" | ${make} Aliased.run" in r.stdout


def test_polyglot_def_registers(cmk):
  # a polyglot's namespace defaults to its `def=` block name, so that registers.
  r = cmk(
    "mk.compile",
    stdin='$(call polyglot.import, def=poly bind=x)\ny:\n\tpoly.run["""z"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"z\" | ${make} poly.run" in r.stdout


def test_polyglot_code_block_sugar_registers(cmk):
  # the `⟦ NAME .. ⟧` polyglot sugar registers NAME (its block-name namespace).
  r = cmk(
    "mk.compile",
    stdin="⟦ poly\ncode line\n⟧ with img=x as container\nz:\n\tpoly.run/arg\n",
  )
  assert r.ok, r.stderr
  assert "${make} poly.run/arg" in r.stdout


def test_unbound_code_sugar_registers(cmk):
  # the `🞹 NAME .. 🞹` unbound-code sugar registers NAME too.
  r = cmk(
    "mk.compile",
    stdin='🞹 widget\nsome code\n🞹\nz:\n\twidget.preview["""x"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"x\" | ${make} widget.preview" in r.stdout


def test_dockerfile_sugar_strips_prefix(cmk):
  # the `⫻ Dockerfile.NAME .. ⫻` image sugar registers NAME (the `Dockerfile.`
  # prefix is dropped, matching how the scaffolded targets are named).
  r = cmk(
    "mk.compile",
    stdin='⫻ Dockerfile.box\nFROM alpine\n⫻\nz:\n\tbox.shell["""hi"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"hi\" | ${make} box.shell" in r.stdout


def test_docker_import_def_registers(cmk):
  # single-image `docker.import(def=Dockerfile.NAME)` registers NAME.
  r = cmk(
    "mk.compile",
    stdin='$(call docker.import, def=Dockerfile.box)\nz:\n\tbox.shell["""hi"""]\n',
  )
  assert r.ok, r.stderr
  assert "printf '%s' \"hi\" | ${make} box.shell" in r.stdout
