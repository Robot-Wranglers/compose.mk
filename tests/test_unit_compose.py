"""Unit tests for pure compose.* helpers (no docker)."""

import pytest

pytestmark = pytest.mark.unit


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
