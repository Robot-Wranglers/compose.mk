"""Implicit compose builds: the base ensure, and the spec key that skips rebuilds.

A service building FROM a cmk-owned tag resolves it to the instance behind it
and builds that first, so no chain needs an explicit base build. A build then
stamps a key over the resolved spec, so an unchanged service reports cached.
Parse-time hops are pinned in test_unit_compose.py.
"""

import subprocess

import pytest

from conftest import COMPOSE_PROJECT

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.compose,
  pytest.mark.dockerfile,
]

BASE_TAG = "compose.mk:probe_base"


def _image_exists(tag) -> bool:
  cp = subprocess.run(["docker", "image", "inspect", tag], capture_output=True)
  return cp.returncode == 0


def _rmi(*tags):
  for tag in tags:
    subprocess.run(["docker", "rmi", "-f", tag], capture_output=True)


def _marker(svc="solo") -> str:
  """Read the file the service spec bakes in, to tell one build from another."""
  cp = subprocess.run(
    ["docker", "run", "--rm", "--entrypoint", "cat", f"{COMPOSE_PROJECT}-{svc}", "/marker"],
    capture_output=True,
    text=True,
  )
  return cp.stdout.strip()


@pytest.fixture
def implicit(project):
  """Load the probe programs, run one, then sweep the tags they produce."""
  project.load("compose-implicit")
  made = [
    BASE_TAG,
    f"{COMPOSE_PROJECT}-solo",
    f"{COMPOSE_PROJECT}-alpha",
    f"{COMPOSE_PROJECT}-beta",
  ]
  _rmi(*made)

  def run(prog, *targets, env=None):
    merged = {"CMK_SUPERVISOR": "1", **(env or {})}
    return project.run("cmk", "run", prog, *targets, env=merged, timeout=600)

  yield run
  compose_file = project.dir / ".tmp.probe.services.yml"
  if compose_file.exists():
    subprocess.run(
      ["docker", "compose", "-f", str(compose_file), "down", "-t", "5"],
      capture_output=True,
      cwd=str(project.dir),
    )
  _rmi(*made)


def test_registered_base_builds_without_an_explicit_prereq(implicit):
  # The core claim: nothing names the base, and it is built anyway.
  assert not _image_exists(BASE_TAG), "probe base must start absent"
  r = implicit("one-svc.cmk", "solo.build")
  assert r.ok, r.stderr
  assert _image_exists(BASE_TAG), "compose.ensure did not build the registered base"


def test_public_base_still_builds(implicit):
  # No owner to ensure, so compose files with public bases are untouched.
  r = implicit("public-base.cmk", "solo.build")
  assert r.ok, r.stderr


def test_second_build_reports_cached(implicit):
  # An unchanged spec is answered from the stamp rather than handed to docker.
  assert implicit("one-svc.cmk", "solo.build").ok
  r = implicit("one-svc.cmk", "solo.build")
  assert r.ok, r.stderr
  assert "cached" in r.stdout + r.stderr


def test_force_defeats_the_stamp(implicit):
  # force=1 rebuilds even when the stamp matches.
  assert implicit("one-svc.cmk", "solo.build").ok
  r = implicit("one-svc.cmk", "solo.build", env={"force": "1"})
  assert r.ok, r.stderr
  assert "cached" not in r.stdout + r.stderr


def test_pruned_service_image_defeats_a_matching_stamp(implicit):
  # A stamp can outlive its image, so presence is checked alongside the key.
  assert implicit("one-svc.cmk", "solo.build").ok
  _rmi(f"{COMPOSE_PROJECT}-solo")
  r = implicit("one-svc.cmk", "solo.build")
  assert r.ok, r.stderr
  assert "cached" not in r.stdout + r.stderr


def test_up_detach_rebuilds_a_stale_spec(implicit):
  # compose builds a missing image but never a changed one; the prereq does.
  assert implicit("one-svc.cmk", "solo.up.detach").ok
  assert _marker() == "solo"
  r = implicit("one-svc-changed.cmk", "solo.up.detach")
  assert r.ok, r.stderr
  assert _marker() == "changed", "up.detach served a stale image"


def test_up_detach_builds_a_missing_base(implicit):
  # Running reaches the base ensure too, not only the service build.
  _rmi(BASE_TAG)
  assert not _image_exists(BASE_TAG), "probe base must start absent"
  r = implicit("one-svc.cmk", "solo.up.detach")
  assert r.ok, r.stderr
  assert _image_exists(BASE_TAG), "up.detach did not reach the base ensure"


def test_dispatch_rebuilds_a_stale_spec(implicit):
  # dispatch runs a target in a fresh container, so it needs a current image.
  r = implicit("dispatch-svc.cmk", "solo.dispatch/show.marker")
  assert r.ok, r.stderr
  assert "solo" in r.stdout
  r = implicit("dispatch-svc-changed.cmk", "solo.dispatch/show.marker")
  assert r.ok, r.stderr
  assert "changed" in r.stdout, "dispatch ran against a stale image"


def test_dispatch_builds_a_missing_base(implicit):
  # Dispatching reaches the base ensure too, not only the service build.
  _rmi(BASE_TAG)
  assert not _image_exists(BASE_TAG), "probe base must start absent"
  r = implicit("dispatch-svc.cmk", "solo.dispatch/show.marker")
  assert r.ok, r.stderr
  assert _image_exists(BASE_TAG), "dispatch did not reach the base ensure"


def test_per_service_stamp_does_not_cover_a_sibling(implicit):
  # Building alpha must not report beta cached; the stamp is per selection.
  assert implicit("two-svc.cmk", "alpha.build").ok
  r = implicit("two-svc.cmk", "beta.build")
  assert r.ok, r.stderr
  assert "cached" not in r.stdout + r.stderr
