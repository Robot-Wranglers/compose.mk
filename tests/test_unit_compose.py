"""Unit tests for pure compose.* helpers (no docker)."""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


@pytest.mark.parametrize(
  "arg,expected",
  [
    ("foo/bar.yml", "bar"),
    ("baz.yaml", "baz"),
    ("x/y/z.yml", "z"),
  ],
)
def test_compose_get_stem(cmk, arg, expected):
  # basename without the .yml/.yaml suffix.
  r = cmk(f"compose.get.stem/{arg}")
  assert r.ok, r.stderr
  assert r.stdout.strip() == expected


# compose.versions/* just greps the file for ${VAR:-default} VERSION vars - no
# docker, so these stay unit (scaffold a compose file in the fixture cwd).
_DC_VER = "services:\n  s:\n    image: alpine:${ALPINE_TEST_VERSION:-3.21.2}\n"


def test_compose_versions(cmk, tmp_path):
  (tmp_path / "dc.yml").write_text(_DC_VER)
  r = cmk("compose.versions/dc.yml")
  assert r.ok, r.stderr
  assert r.stdout.strip() == "ALPINE_TEST_VERSION=3.21.2"


def test_compose_versions_table(cmk, tmp_path):
  (tmp_path / "dc.yml").write_text(_DC_VER)
  r = cmk("compose.versions_table/dc.yml")
  assert r.ok, r.stderr
  assert "| ALPINE_TEST_VERSION | 3.21.2 |" in r.stdout


def test_compose_with_profile(cmk):
  # Sets COMPOSE_PROFILES and runs the given target(s); no docker.
  r = cmk("compose.with_profile/myprofile/flux.ok")
  assert r.ok, r.stderr


# Parse-time half of implicit builds; docker side is test_compose_implicit_build_cmk.py.

_INLINE = "services:\n  b:\n    build:\n      dockerfile_inline: |\n        FROM {}\n"

_DC_FROMS = (
  "services:\n  a:\n    build:\n      dockerfile_inline: |\n"
  "        FROM alpine:3.21.2 AS builder\n        RUN true\n"
  "  b:\n    build:\n      dockerfile_inline: |\n        FROM ${IMG_PROBE}\n"
)

_OWNER_PROBE = (
  "IMG_PROBE := compose.mk:probe_owner\n"
  "container.owner.compose.mk__probe_owner := probe_owner\n"
  "_probe:;@echo '[$(call container.owner.registered,"
  "$(call container.owner.key,$(call mk.expand,"
  "$(word 1,$(call compose.from.tags,dc.yml)))))]'"
)


def _probe(cmk, tmp_path, compose_body, body):
  (tmp_path / "dc.yml").write_text(compose_body)
  w = tmp_path / "probe.mk"
  w.write_text(f"include {COMPOSE_MK}\n{body}\n")
  return cmk("_probe", makefile=str(w))


def test_compose_from_tags_reads_indented_and_multistage(cmk, tmp_path):
  # FROM is indented inside dockerfile_inline, and a stage alias is not a tag.
  r = _probe(
    cmk, tmp_path, _DC_FROMS, "_probe:;@echo '$(call compose.from.tags,dc.yml)'"
  )
  assert r.ok, r.stderr
  assert set(r.stdout.split()) == {"alpine:3.21.2", "${IMG_PROBE}"}


def test_compose_from_tags_empty_for_missing_file(cmk, tmp_path):
  # An absent compose file must not fault the parse.
  r = _probe(
    cmk,
    tmp_path,
    "services: {}\n",
    "_probe:;@echo '[$(call compose.from.tags,nope.yml)]'",
  )
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[]"


def test_registered_base_resolves_to_its_owner(cmk, tmp_path):
  # Every hop at once: expand the reference, key it, find the owning instance.
  r = _probe(cmk, tmp_path, _INLINE.format("${IMG_PROBE}"), _OWNER_PROBE)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[probe_owner]"


def test_unregistered_base_resolves_to_nothing(cmk, tmp_path):
  # A public image owns no registry cell, so ensure emits nothing for it.
  r = _probe(cmk, tmp_path, _INLINE.format("alpine:3.21.2"), _OWNER_PROBE)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[]"


def test_shell_defaulted_base_is_inert_not_fatal(cmk, tmp_path):
  # Shell-style defaulting is a documented degradation: inert, never a fault.
  r = _probe(cmk, tmp_path, _INLINE.format("${IMG_UNSET:-ubuntu:noble}"), _OWNER_PROBE)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "[]"
