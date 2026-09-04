"""First-pass suite for compose.mk's docker.* targets.

Driven through the ``docker_cmk`` fixture, which forces ``CMK_INTERNAL=0`` (so
dispatch really runs containers) and labels every container/image with this
session's ``cmktest=<RUNID>`` so the conftest teardown can remove exactly what
these tests created - and nothing else. Base (pulled) images are kept.

Coverage here is local: info targets, one alpine run, the dispatch chain, a
tiny build, and docker.lambda. Network builds (docker.from.url/github) are
gated behind ``network`` and skipped unless CMK_TEST_NETWORK=1.
"""

import json
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.docker, pytest.mark.needs_docker]

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"


# --- info / no-pull ---------------------------------------------------------


def test_docker_stat(docker_cmk):
  r = docker_cmk("docker.stat")
  assert r.ok, r.stderr
  data = json.loads(r.stdout)
  assert data.get("docker_version")


def test_docker_ps_is_clean_json(docker_cmk):
  r = docker_cmk("docker.ps")
  assert r.ok, r.stderr
  # `docker ps --format json | jq .` => empty, or pretty-printed JSON object(s)
  # (one per running container on the host). Robust check: empty or JSON-ish.
  out = r.stdout.strip()
  assert out == "" or out[0] in "[{"


def test_docker_images_scoped(docker_cmk):
  r = docker_cmk("docker.images")
  assert r.ok, r.stderr  # newline list of compose.mk-repo tags (may be empty)


def test_docker_context_current(docker_cmk):
  r = docker_cmk("docker.context/current")
  assert r.ok, r.stderr
  assert json.loads(r.stdout).get("Name")


# --- run / dispatch (small pull) -------------------------------------------


def test_docker_run_sh_echo(docker_cmk):
  r = docker_cmk(
    "docker.run.sh",
    env={
      "img": "alpine:3.21.2",
      "entrypoint": "none",
      "cmd": "echo HELLO-CMK",
    },
  )
  assert r.ok, r.stderr
  assert "HELLO-CMK" in r.stdout


def test_docker_dispatch_runs_target_in_container(docker_cmk):
  # debian/buildd has make+bash, needed for entrypoint=make dispatch.
  # Run from the repo root: dispatch mounts $PWD as the container workspace
  # and re-runs `make <target>` there, so compose.mk must be in cwd.
  r = docker_cmk(
    "docker.dispatch/flux.ok",
    cwd=REPO,
    env={"img": "debian/buildd:bookworm"},
  )
  assert r.ok, r.stderr


# --- build / lambda ---------------------------------------------------------


def test_docker_from_file_builds_tagged_image(docker_cmk, tmp_path, runid):
  (tmp_path / "Dockerfile").write_text("FROM alpine:3.21.2\nRUN true\n")
  tag = f"compose.mk:cmktest-{runid}"
  r = docker_cmk("docker.from.file/Dockerfile", cwd=tmp_path, env={"tag": tag})
  assert r.ok, r.stderr
  inspect = subprocess.run(
    ["docker", "image", "inspect", tag], capture_output=True
  )
  assert inspect.returncode == 0, f"image {tag} not found after build"


def test_docker_lambda_builds_and_runs(docker_cmk, tmp_path, runid):
  # docker.lambda reads a Dockerfile.<name> def, so supply one via a wrapper
  # makefile that includes compose.mk.
  (tmp_path / "Makefile").write_text(
    f"include {COMPOSE_MK}\n"
    "define Dockerfile.cmktest\n"
    "FROM alpine:3.21.2\n"
    "endef\n"
  )
  marker = f"LAMBDA-{runid}"
  r = docker_cmk(
    "docker.lambda/cmktest",
    cwd=tmp_path,
    makefile=tmp_path / "Makefile",
    env={"cmd": f"echo {marker}"},
  )
  assert r.ok, r.stderr
  assert marker in r.stdout


# --- logs -------------------------------------------------------------------


def _logged_container(runid, marker):
  # A persistent (stopped, not --rm) labeled container with a known log line.
  cid = subprocess.run(
    [
      "docker",
      "run",
      "-d",
      "--label",
      f"cmktest={runid}",
      "alpine:3.21.2",
      "echo",
      marker,
    ],
    capture_output=True,
    text=True,
  ).stdout.strip()
  subprocess.run(["docker", "wait", cid], capture_output=True)
  return cid


def test_docker_logs(docker_cmk, runid):
  cid = _logged_container(runid, "LOGMARKER")
  r = docker_cmk(f"docker.logs/{cid}")
  assert r.ok, r.stderr
  assert "LOGMARKER" in r.stdout + r.stderr


def test_docker_logs_timeout(docker_cmk, runid):
  # docker.logs.timeout follows logs but exits via flux.timeout.sh.
  cid = _logged_container(runid, "LOGMARKER")
  r = docker_cmk(f"docker.logs.timeout/2,{cid}")
  assert r.ok, r.stderr
  assert "LOGMARKER" in r.stdout + r.stderr


# --- network-gated (skipped unless CMK_TEST_NETWORK=1) ----------------------


@pytest.mark.network
def test_docker_from_url(docker_cmk):
  r = docker_cmk(
    "docker.from.url",
    env={
      "url": "https://github.com/alpine-docker/git.git#1.0.38:.",
      "tag": "cmktest-from-url",
    },
  )
  assert r.ok, r.stderr


@pytest.mark.network
def test_docker_from_github(docker_cmk):
  r = docker_cmk(
    "docker.from.github",
    env={"user": "alpine-docker", "repo": "git", "tag": "1.0.38"},
  )
  assert r.ok, r.stderr


# --- read-only info targets (no mutation; safe on a dev box) -----------------


def test_docker_host_ip(docker_cmk):
  r = docker_cmk("docker.host_ip")
  assert r.ok, r.stderr
  assert r.stdout.strip().count(".") == 3  # dotted-quad IP


def test_docker_socket(docker_cmk):
  r = docker_cmk("docker.socket")
  assert r.ok, r.stderr
  assert "://" in r.stdout


def test_docker_size_summary(docker_cmk):
  # `<repo>:<tag> <size>` lines for local images (the session has images).
  r = docker_cmk("docker.size.summary")
  assert r.ok, r.stderr


def test_docker_image_sizes_json(docker_cmk):
  # docker.size.summary piped through the column-zipper -> JSON map.
  r = docker_cmk("docker.image.sizes")
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("{")


def test_docker_images_all_json(docker_cmk):
  r = docker_cmk("docker.images.all")
  assert r.ok, r.stderr
  assert "{" in r.stdout  # `docker images --format json` lines


def test_docker_image_entrypoint(docker_cmk):
  r = docker_cmk("docker.image.entrypoint", env={"img": "alpine:3.21.2"})
  assert r.ok, r.stderr


def test_docker_tags_by_repo(docker_cmk):
  r = docker_cmk("docker.tags.by.repo/alpine")
  assert r.ok, r.stderr
  assert "3.21.2" in r.stdout


# --- run a labeled container (covers docker.run + its docker.start alias) ----


def test_docker_run(docker_cmk):
  r = docker_cmk("docker.run/alpine:3.21.2", env={"cmd": "whoami"})
  assert r.ok, r.stderr
  assert "root" in r.stdout


def test_docker_image_run(docker_cmk):
  # docker.image.run/<img>,<entrypoint> -- entrypoint=none runs cmd directly.
  r = docker_cmk("docker.image.run/alpine:3.21.2,none", env={"cmd": "whoami"})
  assert r.ok, r.stderr
  assert "root" in r.stdout


def test_docker_init(docker_cmk):
  # Read-only: prints docker context + version (and chains to init.compose).
  r = docker_cmk("docker.init")
  assert r.ok, r.stderr


def test_docker_init_compose(docker_cmk):
  r = docker_cmk("docker.init.compose")
  assert r.ok, r.stderr
