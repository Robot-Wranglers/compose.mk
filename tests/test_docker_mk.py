"""Docker-gated mk.docker.* wrappers.

These force the ``compose.mk:`` image prefix around the docker.* targets. Each
test builds a uniquely-tagged ``compose.mk:cmktest-<runid>-*`` image (labeled,
so the label sweep cleans it) and drives the wrapper against it.

mk.docker.clean / mk.docker.prune are intentionally NOT tested: they remove ALL
``compose.mk:*`` images globally, which would nuke a developer's cached images.
"""

import subprocess

import pytest

pytestmark = [pytest.mark.docker, pytest.mark.needs_docker]


def _build(project, runid, suffix):
  """Build compose.mk:cmktest-<runid>-<suffix> from a tiny Dockerfile."""
  tag_suffix = f"cmktest-{runid}-{suffix}"
  project.write("Dockerfile", "FROM alpine:3.21.2\n")
  r = project.run(
    "docker.from.file/Dockerfile", env={"tag": f"compose.mk:{tag_suffix}"}
  )
  assert r.ok, r.stderr
  return tag_suffix


def test_mk_docker_run_sh(project, runid):
  suffix = _build(project, runid, "run")
  r = project.run(
    "mk.docker.run.sh",
    env={"img": suffix, "entrypoint": "none", "cmd": "echo MKD-OK"},
  )
  assert r.ok, r.stderr
  assert "MKD-OK" in r.stdout


def test_mk_docker_image(project, runid):
  # mk.docker.image/% (= mk.docker/% alias) runs the compose.mk:<suffix> image.
  suffix = _build(project, runid, "img")
  r = project.run(
    f"mk.docker.image/{suffix}",
    env={"entrypoint": "none", "cmd": "echo IMGRUN-OK"},
  )
  assert r.ok, r.stderr
  assert "IMGRUN-OK" in r.stdout


def test_mk_docker_rmi(project, runid):
  suffix = _build(project, runid, "rmi")
  assert project.run(f"mk.docker.rmi/{suffix}").ok
  inspect = subprocess.run(
    ["docker", "image", "inspect", f"compose.mk:{suffix}"],
    capture_output=True,
  )
  assert inspect.returncode != 0, "image should be gone after mk.docker.rmi"
