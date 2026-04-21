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


def test_docker_import_mints_container_instance(project):
  # docker.import mints a real `container` KIND instance underneath the legacy
  # verbs, so the namespace also gains .img/.entrypoint/.run + the `<ns>/%` block-run
  # target (the `(| .. |) in <ns>` surface). Parse-only assertion, no image build.
  project.makefile(
    "define Dockerfile.mytool\nFROM alpine:3.21.2\nendef\n"
    "$(call docker.import, def=Dockerfile.mytool namespace=mytool)\n"
    "probe:; @printf 'run=[%s] img=[%s] entrypoint=[%s]\\n' "
    "'$(mytool.run)' '$(mytool.img)' '$(mytool.entrypoint)'\n"
  )
  r = project.run("probe")
  assert r.ok, r.stderr
  assert "run=[_crun/mytool]" in r.stdout
  assert "img=[compose.mk:mytool]" in r.stdout
  assert "entrypoint=[bash]" in r.stdout


def test_docker_import_mint_survives_nested_make(project):
  # The cheap container mint lives ABOVE the CMK_INTERNAL scaffolding guard, so
  # `(| .. |) in <ns>` works at all make levels -- including nested/internal
  # sub-makes (CMK_INTERNAL=1), where the heavyweight verbs are (correctly) absent.
  # Regression guard for the retier: before it, the mint was empty when nested.
  project.makefile(
    "define Dockerfile.mytool\nFROM alpine:3.21.2\nendef\n"
    "$(call docker.import, def=Dockerfile.mytool namespace=mytool)\n"
    "probe:; @printf 'run=[%s] img=[%s]\\n' '$(mytool.run)' '$(mytool.img)'\n"
  )
  r = project.run("probe", env={"CMK_INTERNAL": "1"})
  assert r.ok, r.stderr
  assert "run=[_crun/mytool]" in r.stdout
  assert "img=[compose.mk:mytool]" in r.stdout


def test_docker_import_wires_src_and_file_props(project):
  # docker.import records its build source as a container property: def-mode sets
  # `<ns>.src` (an inline Dockerfile define-block), file-mode sets `<ns>.file` (an
  # on-disk path). The single `.build` verb (from the container KIND) dispatches
  # on these, replacing the old hand-written per-import build recipe.
  project.makefile(
    "define Dockerfile.dtool\nFROM alpine:3.21.2\nendef\n"
    "$(call docker.import, def=Dockerfile.dtool namespace=dtool)\n"
    "$(call docker.import, namespace=ftool file=./Dockerfile.x)\n"
    "probe:; @printf 'dsrc=[%s] fsrc=[%s] ffile=[%s]\\n' "
    "'$(dtool.src)' '$(ftool.src)' '$(ftool.file)'\n"
  )
  r = project.run("probe")
  assert r.ok, r.stderr
  assert "dsrc=[dtool]" in r.stdout
  assert "fsrc=[]" in r.stdout
  assert "ffile=[./Dockerfile.x]" in r.stdout


def test_docker_import_stock_build_is_noop(project):
  # A stock-image import (neither src= nor file=) still gains a `.build` verb from
  # the container KIND, but it no-ops cleanly (exit 0) rather than erroring, so
  # `.build` is always safe to call. Regression guard for the port that moved the
  # build logic into the container ambient.
  project.makefile("$(call docker.import, namespace=stock img=alpine:3.21.2)\n")
  r = project.run("stock.build")
  assert r.ok, r.stderr
