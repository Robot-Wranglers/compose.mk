"""Isolated end-to-end suite for the notebooking demo and its CMK-lang twin.

Both twins drive the SAME jupyter data + kernel containers:

  * demos/notebooking.mk       -- the plain-make demo
  * demos/cmk/notebooking.cmk  -- the CMK-lang twin

They `compose.import` the same docker-compose files, so this suite builds those
containers ONCE and runs both pipelines against the shared docker cache -- the
twins are isolated from other suites, but not from each other.

Two layers:
  * light (always-on, no docker): the .cmk twin transpiles, and both twins
    agree on the compose-scaffolded kernel list.
  * heavy (opt-in, `notebooking` marker + CMK_TEST_NOTEBOOKING=1): the full
    `lab.pipeline` runs end-to-end for each twin, executing every notebook in
    its kernel container.  Skipped by default -- it builds ~7GB of images.
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
CMK = REPO / "demos" / "cmk" / "notebooking.cmk"
NOTEBOOKS = REPO / "demos" / "data" / "jupyter" / "notebooks"

# Invoke the plain .mk by a cwd-relative path: its container-dispatch targets
# re-run `make -f <this makefile>` inside the /lab mount, so an absolute host
# path would not resolve there.  (The .cmk twin goes through `cmk run`, which
# translates the mount path itself.)  This matches how CI + the shebang run it.
MK_REL = "./demos/notebooking.mk"

# The kernels compose.import scaffolds from docker-compose.fmtk.yml, plus the
# in-file kernel.echo target (a kernel NOT coming from the compose file).
EXPECTED_KERNELS = {
  "kernel.z3",
  "kernel.z3_py",
  "kernel.abstract",
  "kernel.alloy",
  "kernel.lean4",
  "kernel.lean4_script",
  "kernel.echo",
}


def _run_mk(*targets, timeout=120):
  # The plain .mk runs directly (it has its own `#!/usr/bin/env make -f`).
  r = subprocess.run(
    [MK_REL, *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def _run_cmk(*targets, timeout=180):
  # The .cmk twin runs through the compiler via `cmk run`.
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(CMK), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


# ------------------------- light layer (always-on) -------------------------


@pytest.mark.compiler
def test_cmk_twin_compiles():
  # The CMK-lang twin transpiles to a Makefile without error.
  r = subprocess.run(
    [str(COMPOSE), "cmk", "compile", str(CMK)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  assert r.returncode == 0, r.stderr


@pytest.mark.unit
def test_kernels_list_parity():
  # Both twins scaffold the same kernels from the shared compose file (no
  # docker needed -- this only parses yaml + introspects targets).
  rmk, omk = _run_mk("kernels.list")
  rck, ock = _run_cmk("kernels.list")
  assert rmk.returncode == 0, omk
  assert rck.returncode == 0, ock
  mk_kernels = {w for w in omk.split() if w.startswith("kernel.")}
  ck_kernels = {w for w in ock.split() if w.startswith("kernel.")}
  assert mk_kernels >= EXPECTED_KERNELS, omk
  # parity: the .cmk twin lists exactly the same kernels as the .mk
  assert mk_kernels == ck_kernels


# ------------------------- heavy layer (opt-in) ----------------------------


@pytest.fixture(scope="module")
def lab_built():
  """Build the jupyter + kernel containers ONCE; both twin pipelines below
  reuse this docker cache (their `lab.init` re-checks the builds = cache hits).
  """
  r, out = _run_mk("tux.require", "jupyter.build", "fmtk.build", timeout=3600)
  assert r.returncode == 0, out
  return True


@pytest.mark.integration
@pytest.mark.notebooking
@pytest.mark.needs_docker
def test_mk_pipeline(lab_built):
  # A green pipeline IS the signal: `jupyter execute --inplace` fails the run
  # if any cell errors.  Notebook outputs are written back into the ipynb, so
  # assert on the executed file rather than the (tty-only) console rendering.
  r, out = _run_mk("lab.pipeline", timeout=1800)
  assert r.returncode == 0, out
  assert "sat" in (NOTEBOOKS / "z3-python.ipynb").read_text()


@pytest.mark.integration
@pytest.mark.notebooking
@pytest.mark.needs_docker
def test_cmk_pipeline(lab_built):
  # Same pipeline via the CMK-lang twin, reusing the docker cache warmed above.
  r, out = _run_cmk("lab.pipeline", timeout=1800)
  assert r.returncode == 0, out
  assert "Hello, world!" in (NOTEBOOKS / "lean-script.ipynb").read_text()
