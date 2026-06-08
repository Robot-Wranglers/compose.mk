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
