"""Cold-start performance benchmark for compose.mk (report-only).

Opt-in and **not wired to CI**. Run via ``tox -e perf-test`` (or ``make
perf-test``). Measures wall-clock *cold-start* (a fresh process per sample) over
N samples (default 10, override with ``CMK_PERF_SAMPLES``) for a few
representative usages:

  1. simple tool-mode:        ``./compose.mk flux.ok``
  2. CMK compile (transpile): ``./compose.mk mk.compile`` (source on stdin)
  3. CMK compile+interpret:   ``./compose.mk mk.interpret! <file>``

(2) and (3) share the same CMK source, so the (3)-vs-(2) delta isolates the
*run* cost on top of pure transpilation.

Unlike the rest of the suite, these run with compose.mk's *real* defaults
(supervisor + hooks ON) -- that's the latency a user actually pays on a cold
invocation. Each sample asserts a clean exit (rc==0); we print
min/median/mean/max but assert no latency threshold (machine-dependent, and this
never runs in CI anyway).
"""

import os
import statistics
import subprocess
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

# Sample count per benchmark (the task asks for 10; override for ad-hoc runs).
SAMPLES = int(os.environ.get("CMK_PERF_SAMPLES", "10"))

# Shared CMK source for the compile-only and compile+interpret benchmarks, so
# their timings are directly comparable.
SAMPLE_CMK = "a:\n\tprintf one\n__main__:\n\tthis.a\n"

# Real-ish cold-start environment: clean, color-free output and no CI-detection
# branch, but otherwise compose.mk's defaults (supervisor + target-rewrite hooks
# ON) so the measurement reflects genuine first-invocation cost.
PERF_ENV = {
  **os.environ,
  "NO_COLOR": "1",
  "TERM": "dumb",
  "GITHUB_ACTIONS": "false",
}


def _bench(
  label, argv, cwd, env=None, stdin=None, samples=SAMPLES, timeout=120
):
  """Run ``argv`` ``samples`` times from ``cwd``, timing each cold start."""
  merged = {**PERF_ENV, **(env or {})}
  times = []
  for i in range(samples):
    t0 = time.perf_counter()
    proc = subprocess.run(
      argv,
      cwd=str(cwd),
      env=merged,
      input=stdin,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      timeout=timeout,
    )
    times.append(time.perf_counter() - t0)
    assert proc.returncode == 0, (
      f"{label}: sample {i + 1}/{samples} exited {proc.returncode}\n"
      f"--- stderr (tail) ---\n{proc.stderr[-2000:]}"
    )
  _report(label, times)
  return times


def _report(label, times):
  """Print a one-line summary (visible with pytest ``-s`` / ``--capture=no``)."""
  print(
    f"\n[perf] {label}: n={len(times)} "
    f"min={min(times):.3f}s "
    f"median={statistics.median(times):.3f}s "
    f"mean={statistics.fmean(times):.3f}s "
    f"max={max(times):.3f}s"
  )


@pytest.mark.perf
def test_perf_flux_ok_coldstart(tmp_path):
  """N cold-start samples of simple tool-mode ``./compose.mk flux.ok``."""
  _bench(
    "flux.ok (tool-mode cold-start)",
    [str(COMPOSE_MK), "flux.ok"],
    cwd=tmp_path,
  )


@pytest.mark.perf
def test_perf_cmk_compile_coldstart(tmp_path):
  """N cold-start samples of pure CMK transpilation (``mk.compile``)."""
  _bench(
    "mk.compile (cmk transpile cold-start)",
    [str(COMPOSE_MK), "mk.compile"],
    cwd=tmp_path,
    stdin=SAMPLE_CMK,
  )


@pytest.mark.perf
def test_perf_cmk_interpret_coldstart(tmp_path):
  """N cold-start samples of a CMK compile+interpret (``mk.interpret!``)."""
  (tmp_path / "perf.cmk").write_text(SAMPLE_CMK)
  _bench(
    "mk.interpret! (cmk compile+interpret cold-start)",
    [str(COMPOSE_MK), "mk.interpret!", "perf.cmk"],
    cwd=tmp_path,
    # interpret!'s yield-epilogue transfers control via a signal supervisor;
    # without one it exits nonzero (see test_interpret_entrypoint_supervisor).
    env={"CMK_SUPERVISOR": "1"},
  )
