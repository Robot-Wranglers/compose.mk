"""Shared pytest harness for the compose.mk test-suite.

The suite drives the real ``./compose.mk`` entrypoint as a subprocess and
asserts on its output. See ``tests/test_unit_streams.py`` for the first layer
(pure ``stream.*`` transforms). Layers 2 (integration project fixtures) and 3
(CMK compiler) will build on the same ``cmk`` fixture.
"""

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

# Deterministic, non-interactive, color-free environment so that stdout carries
# only the functional result (all log.* output goes to stderr) and there are no
# ANSI escapes, supervisor wrappers, or target-rewrite hooks to assert around.
#
#   NO_COLOR=1          -> zeroes every ansi color var (compose.mk:68)
#   CMK_SUPERVISOR=0    -> skip the signal/supervisor wrapper (compose.mk:29)
#   CMK_INTERNAL=1      -> no DIND / import side effects; right default for the
#                          no-docker layers. Integration tests that exercise
#                          *.dispatch/ override this back to "0".
#   CMK_DISABLE_HOOKS=1 -> skip target-rewrite + at-exit hooks (compose.mk:38)
#   TERM=dumb, TRACE=0  -> no terminal/tracing noise
BASE_ENV = {
  "NO_COLOR": "1",
  "CMK_SUPERVISOR": "0",
  "CMK_INTERNAL": "1",
  "CMK_DISABLE_HOOKS": "1",
  "TERM": "dumb",
  "TRACE": "0",
  "GITHUB_ACTIONS": "false",
}


@dataclass
class Result:
  """Outcome of one ``./compose.mk`` invocation."""

  stdout: str
  stderr: str
  returncode: int

  @property
  def ok(self) -> bool:
    return self.returncode == 0


@pytest.fixture
def cmk(tmp_path):
  """Run ``./compose.mk <args>`` with the deterministic env, capturing output.

  Usage::

      r = cmk("stream.comma.to.nl", stdin="a,b,c")
      assert r.ok and r.stdout == "a\\nb\\nc"

  cwd defaults to a pytest ``tmp_path`` so scratch files (``io.mktemp``'s
  ``./.tmp.*`` and ``.flux.stage.*``) land in the temp dir and never pollute
  the repo; pytest removes the dir afterwards.
  """

  def run(*args, stdin="", env=None, cwd=None) -> Result:
    merged = {**os.environ, **BASE_ENV, **(env or {})}
    proc = subprocess.run(
      [str(COMPOSE_MK), *args],
      input=stdin,
      text=True,
      capture_output=True,
      cwd=str(cwd or tmp_path),
      env=merged,
    )
    return Result(proc.stdout, proc.stderr, proc.returncode)

  return run


# --- Docker gating (forward-looking for layers 2/3) -------------------------
# Items marked @pytest.mark.docker / @pytest.mark.integration are auto-skipped
# when no docker daemon is reachable, so the fast no-docker subset still runs.


def _docker_available() -> bool:
  if not shutil.which("docker"):
    return False
  try:
    return (
      subprocess.run(["docker", "info"], capture_output=True).returncode == 0
    )
  except Exception:
    return False


def pytest_collection_modifyitems(config, items):
  if _docker_available():
    return
  skip = pytest.mark.skip(reason="docker daemon not available")
  for item in items:
    if "docker" in item.keywords or "integration" in item.keywords:
      item.add_marker(skip)
