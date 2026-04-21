"""Unit tests for compose.mk's expansion/macro surface (the `$(call …)` and
`${…}` units that have no CLI entrypoint, so target-coverage can't see them).

Each test builds a tiny wrapper Makefile that `include`s compose.mk and calls
the macro from a target, then asserts the result. These are pure (no docker).
Known bugs are pinned with xfail(reason=…, compose.mk:<line>), same as the
namespace suites. Focus: the heavily-used kwarg/arg-binding helpers that the
whole compose.import / docker.run.sh / bind.* machinery depends on.
"""

from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-composition.cmk")]

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrapper(tmp_path, body: str) -> Path:
  mk = tmp_path / "wrap.mk"
  mk.write_text(f"include {COMPOSE_MK}\n{body}\n")
  return mk


# --- mk.unpack.kwargs: the kwarg parser behind compose.import / bind.* -------


def test_mk_unpack_kwargs_extract_default_precedence(cmk, tmp_path):
  # extract a value; fall back to a default for an absent key; an explicit
  # value beats a provided default.
  body = (
    "$(call mk.unpack.kwargs, color=red size=big, color)\n"
    "$(call mk.unpack.kwargs, color=red size=big, shape, circle)\n"
    "$(call mk.unpack.kwargs, pref=explicit, pref, defval)\n"
    "probe:; @printf 'color=[%s] shape=[%s] pref=[%s]\\n' "
    "'$(kwargs_color)' '$(kwargs_shape)' '$(kwargs_pref)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "color=[red] shape=[circle] pref=[explicit]"


def test_mk_unpack_kwargs_quoted_value_with_spaces(cmk, tmp_path):
  body = (
    '$(call mk.unpack.kwargs, label="two words", label)\n'
    "probe:; @printf '[%s]\\n' '$(kwargs_label)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[two words]"


@pytest.mark.xfail(
  reason=(
    "mk.unpack.kwargs never errors on a missing required kwarg: the "
    "`$(if ! $(or …,$(filter undefined,$(origin 3)),…))` guard "
    "(compose.mk:2669) is always truthy (`!` is not a make operator and the "
    "origin-3 filter is non-empty when no default is given), so the "
    "`$(error)` branch is dead and the value is silently empty"
  ),
  strict=False,
)
def test_mk_unpack_kwargs_missing_required_errors(cmk, tmp_path):
  # No default provided for an absent key -> the macro should `$(error)` and
  # make should fail.
  body = "$(call mk.unpack.kwargs, color=red, needme)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok


def test_mk_unpack_kwargs_duplicate_key_errors(cmk, tmp_path):
  # STRICT: a key given more than once is a hard error (no silent last-wins),
  # tagged with the DUPLICATE_KWARG errno and surfacing the
  # offending assignments. See mk.unpack.kwargs in compose.mk.
  body = (
    "$(call mk.unpack.kwargs, prefix=x a.mk prefix=y, prefix, DEF)\n"
    "probe:; @true\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "errno=DUPLICATE_KWARG" in r.stderr
  assert "prefix=x prefix=y" in r.stderr


def test_mk_unpack_kwargs_prefix_key_not_a_false_duplicate(cmk, tmp_path):
  # `def` and `defs` are distinct keys: the duplicate check matches the `key=`
  # boundary, so `def=a defs=b` must NOT trip the strict guard.
  body = (
    "$(call mk.unpack.kwargs, def=a defs=b, def, DEF)\n"
    "probe:; @printf '[%s]\\n' '$(kwargs_def)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[a]"


# --- mk.unpack.kwargs BATCH form: one spec string sets many kwargs_<name> -----


def test_mk_unpack_kwargs_batch_multi_key(cmk, tmp_path):
  # one call, three keys: a bare-required key is extracted, a `k=v` default is
  # applied when the key is absent, and an explicit value beats the default.
  body = (
    "$(call mk.unpack.kwargs, shape=circle color=black, shape color=default size=big)\n"
    "probe:; @printf 'shape=[%s] color=[%s] size=[%s]\\n' "
    "'$(kwargs_shape)' '$(kwargs_color)' '$(kwargs_size)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "shape=[circle] color=[black] size=[big]"


def test_mk_unpack_kwargs_batch_matches_stacked(cmk, tmp_path):
  # a batch spec is equivalent to the historical stacked single-key calls.
  body = (
    "$(call mk.unpack.kwargs, a=1 c=3, a b=B c)\n"
    "probe:; @printf '[%s][%s][%s]\\n' '$(kwargs_a)' '$(kwargs_b)' '$(kwargs_c)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[1][B][3]"


def test_mk_unpack_kwargs_batch_cross_key_default(cmk, tmp_path):
  # a later token's default may reference an earlier unpacked key (left-to-right).
  body = (
    "$(call mk.unpack.kwargs, ns=alice, ns handler=$${kwargs_ns}.handler)\n"
    "probe:; @printf '[%s][%s]\\n' '$(kwargs_ns)' '$(kwargs_handler)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[alice][alice.handler]"


def test_mk_unpack_kwargs_batch_single_quoted_spacey_default(cmk, tmp_path):
  # a single-quoted default keeps its internal spaces...
  absent = (
    "$(call mk.unpack.kwargs, other=x, label='two words')\n"
    "probe:; @printf '[%s]\\n' '$(kwargs_label)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, absent))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[two words]"
  # ...and an explicit value still wins over it.
  present = (
    "$(call mk.unpack.kwargs, label=hi, label='two words')\n"
    "probe:; @printf '[%s]\\n' '$(kwargs_label)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, present))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[hi]"


def test_mk_unpack_kwargs_batch_multiline_spec(cmk, tmp_path):
  # the spec may span lines with `\`; any unquoted whitespace run is one
  # delimiter, so a multi-line spec matches its one-line form.
  body = (
    "$(call mk.unpack.kwargs, a=1 c=3, \\\n"
    "    a          \\\n"
    "    b=B        \\\n"
    "    c          )\n"
    "probe:; @printf '[%s][%s][%s]\\n' '$(kwargs_a)' '$(kwargs_b)' '$(kwargs_c)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[1][B][3]"


def test_mk_unpack_kwargs_batch_duplicate_key_still_errors(cmk, tmp_path):
  # the strict dupe-check fires per key in batch form too.
  body = (
    "$(call mk.unpack.kwargs, prefix=x a.mk prefix=y, prefix=DEF name)\n"
    "probe:; @true\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "errno=DUPLICATE_KWARG" in r.stderr


# --- mk.unpack.args: name -> `name=$(${*} field N)` positional binding --------


def test_mk_unpack_args_binds_named_positionals(cmk, tmp_path):
  # the normal contract: split `${*}` on commas into the named positionals.  A
  # `/`-bearing target (no comma) round-trips fine -- it lands wholly in one field.
  body = (
    "unpack/%:; $(call mk.unpack.args, n target) && "
    'printf \'n=[%s] target=[%s]\\n\' "$$n" "$$target"\n'
  )
  r = cmk("unpack/5,io.time.wait/1", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "n=[5] target=[io.time.wait/1]"


def test_mk_unpack_args_trailing_comma_arg_preserved(cmk, tmp_path):
  # the last name SHOULD absorb the rest of the comma-split (like `-f2-`), so a
  # parametric target carrying its own comma-args survives as one value.
  body = (
    "unpack/%:; $(call mk.unpack.args, n target) && "
    'printf \'n=[%s] target=[%s]\\n\' "$$n" "$$target"\n'
  )
  r = cmk("unpack/5,foo/a,b", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "n=[5] target=[foo/a,b]"


# --- bind.args / bind.posargs: the unified recipe-head arg binder -----------


def test_bind_posargs_splits_on_comma(cmk, tmp_path):
  # bind.posargs == bind.args(from=stem): split the parametric stem into positional
  # `_1st.._5th` + `_head`/`_tail`, comma-delimited by default.
  body = (
    "split/%:; $(call bind.posargs) && printf "
    "'1=%s 2=%s 3=%s tail=%s\\n' "
    '"$$_1st" "$$_2nd" "$$_3rd" "$$_tail"\n'
  )
  r = cmk("split/a,b,c,d", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "1=a 2=b 3=c tail=b,c,d"


def test_bind_posargs_custom_delimiter(cmk, tmp_path):
  # the delimiter is the sole argument: bind.posargs(/) splits on `/`.
  body = (
    "split/%:; $(call bind.posargs, /) && "
    'printf '"'"'1=%s tail=%s\\n'"'"' "$$_1st" "$$_tail"\n'
  )
  r = cmk("split/a/b/c", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "1=a tail=b/c"


def test_bind_args_from_json(cmk, tmp_path):
  # from=json parses a JSON stream on stdin; missing keys take their `key=default`.
  body = (
    "consume:; $(call bind.args, from=json, shape color=blue name=default) "
    "&& printf 'shape=%s color=%s name=%s\\n' "
    '"$$shape" "$$color" "$$name"\n'
  )
  r = cmk(
    "consume",
    stdin='{"shape":"triangle"}',
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert r.stdout.strip() == "shape=triangle color=blue name=default"


def test_bind_args_from_env_defaults_and_required(cmk, tmp_path):
  # from=env: `key=default` fills when unset; a bare `key` is required (present here).
  body = (
    "consume:; $(call bind.args, from=env, color=blue name) "
    '&& printf \'color=%s name=%s\\n\' "$$color" "$$name"\n'
  )
  r = cmk("consume", env={"name": "X"}, makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "color=blue name=X"


def test_bind_args_from_env_missing_required_fails(cmk, tmp_path):
  # A bare required var that is unset -> non-zero exit.
  body = (
    "consume:; $(call bind.args, from=env, name) "
    "&& printf 'name=%s\\n' \"$$name\"\n"
  )
  r = cmk("consume", makefile=_wrapper(tmp_path, body))
  assert not r.ok


def test_bind_args_unknown_source_errors(cmk, tmp_path):
  # an unrecognised from= hard-errors (the $(error) fires when the recipe expands).
  body = "consume:; $(call bind.args, from=xml, a b) && true\n"
  r = cmk("consume", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "bind.args: unknown source" in r.stderr


# --- small pure helpers ------------------------------------------------------


def test_io_string_hash(cmk, tmp_path):
  # Replaces spaces, dots, and slashes with underscores (cache-key slug).
  body = "probe:; @printf '%s\\n' '$(call io.string.hash,a.b c/d)'\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "a_b_c_d"


def test_bind_def_to_env(cmk, tmp_path):
  # Reads a define-block into a named env var.
  body = (
    "define greeting\nhello world\nendef\n"
    "probe:; $(call def.to.env, greeting, GREET) "
    "&& printf 'GREET=[%s]\\n' \"$$GREET\"\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "GREET=[hello world]" in r.stdout


def test_io_mktemp_creates_and_scopes_tempfile(cmk, tmp_path):
  # io.mktemp exports $tmpf (a ./.tmp.* file) that exists during the recipe.
  body = 'probe:; $(call io.mktemp) && test -f "$$tmpf" && echo "OK:$$tmpf"\n'
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "OK:./.tmp." in r.stdout


def test_io_mktempd_creates_tempdir(cmk, tmp_path):
  # io.mktempd exports $tmpd (a ./.tmp.* directory) that exists during the recipe.
  body = 'probe:; $(call io.mktempd) && test -d "$$tmpd" && echo "OK:$$tmpd"\n'
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "OK:./.tmp." in r.stdout


def test_io_mktemp_custom_var(cmk, tmp_path):
  # _io.mktemp targets a caller-named var instead of the default $tmpf.
  body = 'probe:; $(call _io.mktemp, var=derived) && test -f "$$derived" && echo "OK:$$derived"\n'
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "OK:./.tmp." in r.stdout


def test_io_declare_stack_codegen_fresh(cmk, tmp_path):
  # declare.stack code-gens an exported, per-run-unique stack-name var
  # when the name is UNDEFINED (the macro wraps its own $(eval)).
  body = (
    "$(call declare.stack,MY_STACK)\n"
    "probe:; @printf 'name=[%s]\\n' '$(MY_STACK)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "name=[.tmp.MY_STACK." in r.stdout  # fresh, namespaced by the var


def test_io_declare_stack_origin_guard_preserves(cmk, tmp_path):
  # the origin-guard reuses an already-defined value (so sub-makes inherit one
  # shared file) instead of generating a new name.
  body = (
    "MY_STACK := preset.json\n"
    "$(call declare.stack,MY_STACK)\n"
    "probe:; @printf 'name=[%s]\\n' '$(MY_STACK)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "name=[preset.json]" in r.stdout


# --- include.file: include one explicit makefile, clean error if absent ----


def test_mk_include_file_includes_present(cmk, tmp_path):
  # include.file includes a present makefile, so its definitions become
  # available to the includer.
  inc = tmp_path / "inc.mk"
  inc.write_text("FROM_INC := yes\n")
  body = (
    f"$(call include.file, {inc})\n"
    "probe:; @printf 'FROM_INC=[%s]\\n' '$(FROM_INC)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "FROM_INC=[yes]" in r.stdout


def test_mk_include_file_missing_errors(cmk, tmp_path):
  # A missing target fails cleanly (nonzero) rather than silently no-op'ing.
  body = "$(call include.file, /no/such/file.mk)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok


# --- mk.kwargs.get: the fork-free, value-RETURNING kwarg getter -------------
# The pure-make counterpart to mk.unpack.kwargs (which SETS kwargs_<key>).
# `$(call mk.kwargs.get, <args>, <key>)` -> the bare value, or empty.  Factors
# out the `$(patsubst K=%,%,$(filter K=%,..))` idiom used across io.stack/
# io.channel/mk.id.


def test_mk_kwargs_get_returns_value_or_empty(cmk, tmp_path):
  body = (
    "probe:; @printf 'ns=[%s] tr=[%s] miss=[%s]\\n' "
    "'$(call mk.kwargs.get,namespace=alice transport=socket,namespace)' "
    "'$(call mk.kwargs.get,namespace=alice transport=socket,transport)' "
    "'$(call mk.kwargs.get,namespace=alice,missing)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "ns=[alice] tr=[socket] miss=[]"


def test_mk_kwargs_get_tolerates_spaced_key(cmk, tmp_path):
  # the key arg is `$(strip)`-ed, so `, namespace` (leading space) still works.
  body = "probe:; @printf '[%s]\\n' '$(call mk.kwargs.get, namespace=bob x=1 , namespace)'\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[bob]"


def test_mk_kwargs_get_value_with_spaces(cmk, tmp_path):
  body = (
    "probe:; @printf '[%s]\\n' "
    "\"$(call mk.kwargs.get,entrypoint=uv cmd='run --script',cmd)\"\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[run --script]"


# --- class: the mixin-composition metaclass (core) ---------------------------
# Exercised here at the plain-make level (mixins as ordinary `define`s), so the
# test covers the core macro independent of the cmk `:=` sugar.  Single-arg:
# `class(Name M1 M2 ..)` -- name first, mixin chain the rest.  End-to-end
# coverage over the demos lives in test_banana_oop_cmk.py.


def test_class_composes_mixins_onto_instance(cmk, tmp_path):
  # two mixin templates keyed on ${self}; the class stamps both onto `rex`.
  body = (
    "define Walk\n${self}.walk:; @echo walk-${self}\nendef\n"
    "define Speak\n${self}.speak:; @echo speak-${self}\nendef\n"
    "$(call cmk.class,Dog Walk Speak)\n"
    "$(call Dog,rex)\n"
  )
  mk = _wrapper(tmp_path, body)
  assert cmk("rex.walk", makefile=mk).stdout.strip() == "walk-rex"
  assert cmk("rex.speak", makefile=mk).stdout.strip() == "speak-rex"


def test_class_self_from_namespace_kwarg(cmk, tmp_path):
  # ${self} = the `namespace=` kwarg when the instance is called kwarg-style.
  body = (
    "define M\n${self}.id:; @echo id-${self}\nendef\n"
    "$(call cmk.class,K M)\n"
    "$(call K,namespace=alice transport=socket)\n"
  )
  r = cmk("alice.id", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "id-alice"


def test_class_mixin_scoping_is_per_chain(cmk, tmp_path):
  # a class gets only the methods of the mixins in its chain -- Base(cow) has
  # no `Extra` method, so cow.extra must not exist.
  body = (
    "define Base\n${self}.base:; @echo base\nendef\n"
    "define Extra\n${self}.extra:; @echo extra\nendef\n"
    "$(call cmk.class,Small Base)\n"
    "$(call cmk.class,Big Base Extra)\n"
    "$(call Small,cow)\n$(call Big,rex)\n"
  )
  mk = _wrapper(tmp_path, body)
  assert cmk("rex.extra", makefile=mk).stdout.strip() == "extra"
  r = cmk("cow.extra", makefile=mk)
  assert not r.ok and "No rule to make target" in (r.stdout + r.stderr)


# --- m5.def.! (was mk.def.create): the self-evaling def-form factory ----------
# Creates NAME as `NAME = $(eval $(call TMPL,$(strip $1)))` from a `define TMPL`
# template.  `$(call NAME, args)` then injects the template instantiated with
# args.  The primitive under lang.ctor.__new__, `class`, mk.memoize, and *.import.


def test_mk_def_create_mints_self_instantiating_form(cmk, tmp_path):
  body = (
    "define _widget\n$(1).on:; @echo $(1)-on\nendef\n"
    "$(call m5.def.!, declare.widget, _widget)\n"
    "$(call declare.widget, lamp)\n"
  )
  r = cmk("lamp.on", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "lamp-on"


def test_class_is_built_on_mk_def_create(cmk, tmp_path):
  # the class metaclass generates a per-class chain template (`Name.__tmpl`)
  # and mints the class from it via mk.def.create -- the tier is real.
  body = (
    "define X\n${self}.m:; @echo m-${self}\nendef\n"
    "$(call cmk.class, Klass X)\n"
    "probe:; @printf '[%s]\\n' "
    "'$(if $(filter undefined,$(origin Klass.__tmpl)),ABSENT,PRESENT)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[PRESENT]"


# --- lang.ctor.__new__: def -> self-evaling ctor MACRO (backs the `constructor` kw) ----
# `$(call lang.ctor.__new__, def=NAME)` reifies the template NAME already holds into a
# self-evaling constructor whose template is auto-handed the banana bodies -- ${self} =
# body1's name (the `def=` value), ${body2}/${body3}.. = the extra payload names.  The
# public `constructor` keyword is a thin alias for it; exercised directly here at the
# plain-make level with the `def=NAME def2=NAME__2` kwargs a banana emits; the end-to-end
# (docker) coverage is demos/cmk/banana-composition.cmk.


def test_future_ctor_bakes_self_and_bodies_per_instance(cmk, tmp_path):
  # two instances from one ctor: the bindings must bake into each target at
  # declare-time, not leak as globals the last declaration clobbers.  (The copy
  # stays recursive-flavored -- a `:=` stash bakes nothing and both targets
  # would print the last instance.)  Also pins the symmetric positional names:
  # ${body1} == ${self} (the `def=` value), ${body2} = the def2 payload.
  body = (
    "define declare.job\n${self}:; @printf '[%s|%s|%s]\\n' '${self}' '${body1}' '${body2}'\nendef\n"
    "$(call lang.ctor.__new__, def=declare.job)\n"
    "$(call declare.job, def=alpha def2=alpha__2)\n"
    "$(call declare.job, def=beta def2=beta__2)\n"
  )
  mk = _wrapper(tmp_path, body)
  assert cmk("alpha", makefile=mk).stdout.strip() == "[alpha|alpha|alpha__2]"
  assert cmk("beta", makefile=mk).stdout.strip() == "[beta|beta|beta__2]"


def test_future_ctor_body_names_read_payloads(cmk, tmp_path):
  # ${self}/${body2} are the define NAMES, so mk.def.read/<name> yields the
  # payload TEXT at recipe time -- the constructor never hand-unpacks kwargs.
  body = (
    "define declare.cat\n${self}:; @${make} mk.def.read/${body2}\nendef\n"
    "$(call lang.ctor.__new__, def=declare.cat)\n"
    "define alpha\nFIRST-payload\nendef\n"
    "define alpha__2\nSECOND-payload\nendef\n"
    "$(call declare.cat, def=alpha def2=alpha__2)\n"
  )
  r = cmk("alpha", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "SECOND-payload"


def test_constructor_keyword_forwards_to_ctor(cmk, tmp_path):
  # `constructor` is the banana-facing forwarder: `$(call cmk.constructor, def=NAME)`
  # -- what `constructor NAME(|..|)` lowers to -- turns the define NAME already
  # holds into the self-evaling ctor, same as `$(call lang.ctor.__new__, def=NAME)`.
  body = (
    "define declare.job\n${self}:; @printf '[%s|%s]\\n' '${self}' '${body2}'\nendef\n"
    "$(call cmk.constructor, def=declare.job)\n"
    "$(call declare.job, def=alpha def2=alpha__2)\n"
  )
  r = cmk("alpha", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[alpha|alpha__2]"


def test_awk_minter_tiers(cmk, tmp_path):
  # The 3-level awk-block minter hierarchy, each reusing the one below:
  #   lang.awk.export(main=<block>)  -> the `_awklang_<name>` export ONLY
  #   lang.awk.comp(..)              -> + the `lang.comp.stage.<name>` awk pipe-fragment
  #   lang.awk.stage(..)             -> + its `lang.comp.pipeline.<name>` stage target
  # Verify each tier mints exactly its level and nothing above it.
  body = (
    "define .awk.ex\n  { print }\nendef\n"
    "define .awk.co\n  { print }\nendef\n"
    "define .awk.st\n  { print }\nendef\n"
    "$(call lang.awk.export, main=.awk.ex)\n"
    "$(call lang.awk.comp, main=.awk.co)\n"
    "$(call lang.awk.stage, main=.awk.st)\n"
    "O=$(if $(filter undefined,$(origin $(1))),no,yes)\n"
    "probe:; @printf 'exp=%s%s%s stg=%s%s%s\\n' "
    "'$(call O,_awklang_ex)' '$(call O,_awklang_co)' '$(call O,_awklang_st)' "
    "'$(call O,lang.comp.stage.ex)' '$(call O,lang.comp.stage.co)' '$(call O,lang.comp.stage.st)'\n"
  )
  mk = _wrapper(tmp_path, body)
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert "exp=yesyesyes" in r.stdout            # all three tiers export `_awklang_<name>`
  assert "stg=noyesyes" in r.stdout             # only comp + stage mint the `lang.comp.stage.<name>` fragment
  # the pipeline stage TARGET (a target, not a var) -- only lang.awk.stage mints it
  assert cmk("lang.comp.pipeline.st", stdin="x:; @true\n", makefile=mk).returncode == 0
  assert "No rule to make target" in cmk("lang.comp.pipeline.co", makefile=mk).stderr
