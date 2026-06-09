"""Integration tests: scaffold a real mini-project and run targets against it.

Uses the `project` fixture (a temp project dir) to either write files inline or
`load()` a prebuilt tree from tests/fixtures/. First family covered:
Dockerfile.* - the bridge from an on-disk / embedded Dockerfile to a built
image. Every artifact is cmktest-labeled via docker_cmk and swept on teardown.
"""

import subprocess

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]


def _image_exists(tag) -> bool:
  cp = subprocess.run(["docker", "image", "inspect", tag], capture_output=True)
  return cp.returncode == 0


def test_dockerfile_from_fs_builds_ondisk_file(project, runid):
  # On-disk Dockerfile written inline; built via the filesystem path.
  project.write("Dockerfile", "FROM alpine:3.21.2\n")
  tag = f"compose.mk:cmktest-{runid}-fs"
  r = project.run("Dockerfile.from.fs/Dockerfile", env={"tag": tag})
  assert r.ok, r.stderr
  assert _image_exists(tag)


def test_dockerfile_build_from_embedded_def(project):
  # Fixture: a Makefile that includes compose.mk and defines Dockerfile.app.
  project.load("dockerfile-def")
  r = project.run("Dockerfile.build/app")
  assert r.ok, r.stderr
  assert _image_exists("compose.mk:app")


def test_build_context_includes_scaffolded_files(project, runid):
  # The Dockerfile COPYs payload.txt - proving the build context is the
  # scaffolded project dir - then we run the image and read the file back.
  project.load("dockerfile-copy")
  tag = f"compose.mk:cmktest-{runid}-copy"
  build = project.run("Dockerfile.from.fs/Dockerfile", env={"tag": tag})
  assert build.ok, build.stderr
  run = project.run(
    "docker.run.sh",
    env={"img": tag, "entrypoint": "none", "cmd": "cat /payload.txt"},
  )
  assert run.ok, run.stderr
  assert "payload-marker-7f3a" in run.stdout


def test_docker_import_def_generated(project):
  # docker.import.def scaffolds run/dispatch/clean targets for an inline
  # Dockerfile def. Covers the generated <ns> / <ns>.build / <ns>.dispatch /
  # <ns>.clean templates (the bare <ns> runs a command via docker.run.sh; with
  # entrypoint=none the command runs directly instead of under bash).
  project.load("docker-import")
  assert project.run("mytool.build").ok
  r = project.run("mytool", env={"cmd": "whoami", "entrypoint": "none"})
  assert r.ok, r.stderr
  assert "root" in r.stdout
  assert project.run("mytool.dispatch/flux.ok").ok
  assert project.run("mytool.clean").ok
