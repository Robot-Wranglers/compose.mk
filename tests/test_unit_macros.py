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

pytestmark = pytest.mark.unit

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


@pytest.mark.xfail(
  reason=(
    "mk.unpack.kwargs mangles quoted values containing spaces: the "
    '`printf "${1}"` (compose.mk:2666) doesn\'t preserve embedded quotes, '
    'so key="two words" yields only `two`'
  ),
  strict=False,
)
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
  # tagged with the CMK_UNPACKED_DUPLICATE_KWARG sentinel and surfacing the
  # offending assignments. See mk.unpack.kwargs in compose.mk.
  body = (
    "$(call mk.unpack.kwargs, prefix=x a.mk prefix=y, prefix, DEF)\n"
    "probe:; @true\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_UNPACKED_DUPLICATE_KWARG" in r.stderr
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


@pytest.mark.xfail(
  reason=(
    "mk.unpack.args binds each name to a SINGLE field via "
    "`cut -d, -f<n>` (compose.mk:3877), so the LAST positional is truncated at "
    "its first comma: `5,foo/a,b` yields target=`foo/a`, dropping `,b`.  A "
    "trailing target that itself takes comma-args (e.g. `flux.loop/5,build/x,y`) "
    "can't round-trip -- the flux.if.then/do.when/starmap family use an explicit "
    "`cut -d, -f2-` for exactly this reason."
  ),
  strict=False,
)
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


# --- bind.posargs / _bind.posargs: positional `${*}` splitting ---------------


def test_bind_posargs_splits_on_comma(cmk, tmp_path):
  body = (
    "split/%:; $(call bind.posargs) && printf "
    "'1=%s 2=%s 3=%s tail=%s\\n' "
    '"$$_1st" "$$_2nd" "$$_3rd" "$$_tail"\n'
  )
  r = cmk("split/a,b,c,d", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "1=a 2=b 3=c tail=b,c,d"


# --- bind.args.from_json / from_env: decorator kwarg backends ----------------


def test_bind_args_from_json(cmk, tmp_path):
  # Parse keys from JSON on stdin; fill `key=default` for absent keys.
  body = (
    "consume:; $(call bind.args.from_json, shape color=blue name=default) "
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
  # `key=default` fills when unset; a bare `key` is required (present here).
  body = (
    "consume:; $(call bind.args.from_env, color=blue name) "
    '&& printf \'color=%s name=%s\\n\' "$$color" "$$name"\n'
  )
  r = cmk("consume", env={"name": "X"}, makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "color=blue name=X"


def test_bind_args_from_env_missing_required_fails(cmk, tmp_path):
  # A bare required var that is unset -> non-zero exit.
  body = (
    "consume:; $(call bind.args.from_env, name) "
    "&& printf 'name=%s\\n' \"$$name\"\n"
  )
  r = cmk("consume", makefile=_wrapper(tmp_path, body))
  assert not r.ok


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
    "probe:; $(call bind.def.to.env, greeting, GREET) "
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
