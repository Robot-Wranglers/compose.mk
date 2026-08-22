"""Implicit image build: which dispatch forms reach container.ensure.

A buildable container registers its image tag at mint, and container.ensure
resolves the owner of an instance's tag, so a box declared only by another
instance's image builds that owner on first dispatch instead of needing a
manual build prereq.

Two seams reach the runtime: the container run dispatch, which bound
code-objects and dsl programs both delegate to, and the dispatch target. Each
ensures the tag owner first, so every form below covers one of them.

Companion to demos/cmk/machines-nested.cmk, which relies on the sibling case.
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.machine,
  pytest.mark.dockerfile,
  pytest.mark.covers_demo("machines-nested.cmk"),
]

MARKER = "implicit-build-ok"

PREAMBLE = """\
from cmk import container, machine, dsl, Dockerfile

Dockerfile {base}(entrypoint=sh)(|
  FROM alpine:3.21.2
  RUN apk add -q --update --no-cache coreutils bash gawk make
|)

container box(img=${{{base}.img}} entrypoint=sh)(| |)
machine mach(img=${{{base}.img}} entrypoint=sh)(| |)
dsl by_machine(machine=box)(| |)
dsl by_img(img=${{{base}.img}} entrypoint=sh feed=file)(| |)

{base}.polyglot poly(|
  echo "{marker}"
|)

by_machine prog_machine(|
  echo "{marker}"
|)

by_img prog_img(|
  echo "{marker}"
|)

in_container:
  (| echo "{marker}" |) in box

in_machine:
  (| echo "{marker}" |) in mach

env_trailer:
  (| echo "{marker}" |) in box {{env=HOME}}

dsl_machine:
  prog_machine()

dsl_img:
  prog_img()

polyglot:
  poly()

dispatch:
  ${{make}} box.dispatch/flux.ok
"""


def _image_exists(tag) -> bool:
  cp = subprocess.run(["docker", "image", "inspect", tag], capture_output=True)
  return cp.returncode == 0


@pytest.fixture
def implicit(request, docker_cmk, runid):
  """Write the probe source under a per-test image tag, run one form, sweep."""
  base = f"cmktest_{runid}_{request.node.name.split('[')[0]}"
  tag = f"compose.mk:{base}"
  src = REPO / f".tmp.{base}.cmk"
  src.write_text(PREAMBLE.format(base=base, marker=MARKER))

  def run(target):
    subprocess.run(["docker", "rmi", "-f", tag], capture_output=True)
    assert not _image_exists(tag), "probe tag must start absent"
    r = docker_cmk(
      "cmk",
      "run",
      src.name,
      target,
      cwd=REPO,
      timeout=600,
      env={"CMK_SUPERVISOR": "1"},
    )
    return r, _image_exists(tag)

  yield run
  src.unlink(missing_ok=True)
  subprocess.run(["docker", "rmi", "-f", tag], capture_output=True)


def test_in_container_builds_the_tag_owner(implicit):
  # the sibling case: the box carries no recipe of its own, only the base tag
  r, built = implicit("in_container")
  assert r.ok, r.stderr
  assert built
  assert MARKER in r.stdout


def test_in_machine_builds_the_tag_owner(implicit):
  # a bare machine carrying an image routes through the same run dispatch
  r, built = implicit("in_machine")
  assert r.ok, r.stderr
  assert built


def test_env_trailer_builds_the_tag_owner(implicit):
  # an env trailer is still a dispatch, not a callform
  r, built = implicit("env_trailer")
  assert r.ok, r.stderr
  assert built


def test_dsl_backed_by_machine_builds_the_tag_owner(implicit):
  # a dsl backed by a named container delegates its invoke to that container
  r, built = implicit("dsl_machine")
  assert r.ok, r.stderr
  assert built


def test_dsl_bound_by_img_builds_the_tag_owner(implicit):
  # a dsl bound by tag resolves the owner with no named container between
  r, built = implicit("dsl_img")
  assert r.ok, r.stderr
  assert built


def test_polyglot_call_builds_the_tag_owner(implicit):
  # a bound code-object delegates to the machine run hook, which ensures first
  r, built = implicit("polyglot")
  assert r.ok, r.stderr
  assert built
  assert MARKER in r.stdout


def test_dispatch_builds_the_tag_owner(implicit):
  # the dispatch target reads the tag directly and ensures its owner first
  r, built = implicit("dispatch")
  assert r.ok, r.stderr
  assert built
