"""Nested indentation survives the trip from a code-object body to its interpreter.

A bound code-object hands its machine the body BY NAME, so the feed discipline
materializes the file at recipe time. Handing over the materialized text instead
would cross a callform argument, and the argument accessors are strip-normalized
by construction, which collapses every nested indent to a single space.

That regression is invisible to whitespace-insensitive guests, so these probes
use Python, where a lost indent is a hard error. The dsl arm is the seam that
was already correct; the polyglot arm is the one that regressed and was healed
by routing it through the same seam. Both arms run here so the two cannot drift
apart again.

See scratch/polyglot-indent-transport.md for the history.
"""

import subprocess

import pytest

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.code_object,
  pytest.mark.dsl,
]

SRC = """\
from cmk import Dockerfile, container, dsl

Dockerfile pyimg(|
  FROM python:3.11-slim
  ENTRYPOINT ["python3"]
|)

container pybox(img=${pyimg.img} entrypoint=python3)(| |)
dsl pylang(machine=pybox)(| |)

pyimg.polyglot via_polyglot(|
  def f(x):
      if x > 1:
          return "polyglot-nested-ok"
      return "flat"
  print(f(2))
|)

pylang via_dsl(|
  def f(x):
      if x > 1:
          return "dsl-nested-ok"
      return "flat"
  print(f(2))
|)

polyglot:
  via_polyglot()

dslprog:
  via_dsl()
"""


@pytest.fixture
def seams(request, docker_cmk, runid, tmp_path):
  """Write the two-arm probe into the repo and run one arm."""
  from pathlib import Path

  repo = Path(__file__).resolve().parent.parent
  src = repo / f".tmp.cmktest_{runid}_indent.cmk"
  src.write_text(SRC)

  def run(target):
    return docker_cmk(
      "cmk",
      "run",
      src.name,
      target,
      cwd=repo,
      timeout=900,
      env={"CMK_SUPERVISOR": "1"},
    )

  yield run
  src.unlink(missing_ok=True)
  # by id, so the content-hashed tag goes with the plain one and each arm rebuilds
  ids = subprocess.run(
    ["docker", "images", "-q", "--filter", "reference=compose.mk:pyimg*"],
    capture_output=True, text=True,
  ).stdout.split()
  if ids:
    subprocess.run(["docker", "rmi", "-f", *ids], capture_output=True)


def test_polyglot_preserves_nested_indentation(seams):
  # the healed arm: a body bound straight to its image
  r = seams("polyglot")
  assert r.ok, r.stderr
  assert "polyglot-nested-ok" in r.stdout + r.stderr


def test_dsl_preserves_nested_indentation(seams):
  # the reference arm: already correct, kept here so the seams stay together
  r = seams("dslprog")
  assert r.ok, r.stderr
  assert "dsl-nested-ok" in r.stdout + r.stderr
