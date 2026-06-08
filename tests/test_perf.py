"""Cold-start performance benchmark for compose.mk (report-only).

Opt-in: **not gated on push/PR**. Runs on-demand via the Perf Tests workflow
(``.github/workflows/perf-tests.yml``); locally via ``tox -e perf-test``
(or ``make perf-test``). Measures wall-clock *cold-start* (a fresh process per sample) over
N samples (default 10, override with ``CMK_PERF_SAMPLES``) for a few
representative usages:

  1. simple tool-mode:        ``./compose.mk flux.ok``
  2. CMK compile (transpile): ``./compose.mk mk.compile`` (source on stdin)
  3. CMK compile+interpret:   ``./compose.mk mk.interpret! <file>``
  4. headless TUI bring-up:   ``./compose.mk tux.open/...`` (needs docker)

(2) and (3) share the same CMK source, so the (3)-vs-(2) delta isolates the
*run* cost on top of pure transpilation. (1)-(3) are pure in-process cold-starts
(no docker); (4) measures the latency to spin the tux container and load the
tmuxp session, and is auto-skipped when no docker daemon is available.

Unlike the rest of the suite, these run with compose.mk's *real* defaults
(supervisor + hooks ON) -- that's the latency a user actually pays on a cold
invocation. Each sample asserts a clean exit (rc==0); we print
min/median/mean/max but assert no latency threshold (machine-dependent, so this
is a report, not a PR gate).
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
  label,
  argv,
  cwd,
  env=None,
  stdin=None,
  samples=SAMPLES,
  timeout=120,
  marker=None,
  pre=None,
):
  """Run ``argv`` ``samples`` times from ``cwd``, timing each cold start.

  Success per sample is ``rc == 0`` by default; pass ``marker`` to instead
  require that substring in the combined output and ignore the exit code -- for
  flows that legitimately end nonzero headless (e.g. a TUI whose final
  ``tmux attach`` fails without a tty). ``pre`` (if given) is called before each
  sample, OUTSIDE the timed region -- used to reset shared state so every sample
  is a genuine cold start.
  """
  merged = {**PERF_ENV, **(env or {})}
  times = []
  for i in range(samples):
    if pre is not None:
      pre()
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
    if marker is None:
      assert proc.returncode == 0, (
        f"{label}: sample {i + 1}/{samples} exited {proc.returncode}\n"
        f"--- stderr (tail) ---\n{proc.stderr[-2000:]}"
      )
    else:
      out = proc.stdout + proc.stderr
      assert marker in out, (
        f"{label}: sample {i + 1}/{samples} missing marker {marker!r}\n"
        f"--- output (tail) ---\n{out[-2000:]}"
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


# Fewer samples for the TUI: each one spins a fresh tux container + tmuxp load,
# so it is far heavier than the in-process cold-starts above.
TUI_SAMPLES = max(1, min(SAMPLES, 3))


@pytest.mark.perf
@pytest.mark.needs_docker
def test_perf_tui_bringup_coldstart():
  """N cold-start samples of headless TUI bring-up (``tux.open`` -> tmuxp).

  Measures the wall-clock to spin the ``compose.mk:tux`` container and load the
  tmuxp session -- the latency before the UI is interactive. Headless, so stdin
  is closed and success is the tmuxp ``Loaded workspace`` marker, NOT rc==0 (the
  final ``tmux attach`` fails without a tty). The tux image is built once up
  front so its one-time build cost is excluded from the samples; needs docker
  (auto-skipped otherwise). Invoked by the RELATIVE ``./compose.mk`` from the
  repo so the in-container ``make -f`` paths resolve via the /workspace mount.
  """
  proj = "cmkperftui"
  env = {"CMK_SUPERVISOR": "1", "COMPOSE_PROJECT_NAME": proj}
  before = set(REPO.glob(".tmp.*"))

  def _reset():
    # Each sample must be a genuine cold start. The tmux socket is RELATIVE
    # (`tmux.sock`) so it lands in the workspace (repo) -- a leftover socket (or a
    # still-running tux container holding it) makes the next `tux.open` attach to
    # the existing session instead of loading fresh (no "Loaded workspace"). So
    # tear down the project's containers/volumes and remove the stale socket.
    subprocess.run(
      ["docker", "compose", "-p", proj, "down", "-v", "--remove-orphans"],
      cwd=str(REPO),
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
    )
    ids = subprocess.run(
      ["docker", "ps", "-aq", "--filter", f"name={proj}"],
      capture_output=True,
      text=True,
    ).stdout.split()
    if ids:
      subprocess.run(
        ["docker", "rm", "-f", *ids],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
      )
    (REPO / "tmux.sock").unlink(missing_ok=True)

  # Warm the tux image (not timed); skip if it can't be built (e.g. no network).
  warm = subprocess.run(
    ["./compose.mk", "tux.require"],
    cwd=str(REPO),
    env={**PERF_ENV, **env},
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=1800,
  )
  if warm.returncode != 0:
    pytest.skip(
      f"tux image unavailable (tux.require rc={warm.returncode}); "
      f"skipping TUI perf:\n{warm.stderr[-1500:]}"
    )
  try:
    _bench(
      "tux.open (headless TUI bring-up cold-start)",
      ["./compose.mk", "tux.open/flux.ok,flux.ok"],
      cwd=REPO,
      env=env,
      stdin="",
      samples=TUI_SAMPLES,
      timeout=300,
      marker="Loaded workspace",
      pre=_reset,
    )
  finally:
    _reset()
    for p in REPO.glob(".tmp.*"):
      if p not in before:
        try:
          p.unlink()
        except OSError:
          pass
