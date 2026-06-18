"""Cold-start performance benchmark for compose.mk (report-only).

Opt-in: **not gated on push/PR**. Runs on-demand via the Perf Tests workflow
(``.github/workflows/perf-tests.yml``); locally via ``tox -e perf-test``
(or ``make perf-test``). Measures wall-clock *cold-start* (a fresh process per
sample) over N samples (default 10, override with ``CMK_PERF_SAMPLES``) for a few
representative usages:

  1. simple tool-mode:        ``compose.mk flux.ok``
  2. CMK compile (transpile): ``compose.mk mk.compile`` (source on stdin)
  3. CMK compile+interpret:   ``compose.mk mk.interpret! <file>``
  4. headless TUI bring-up:   ``./compose.mk tux.open/...`` (needs docker)

(2) and (3) share the same CMK source, so the (3)-vs-(2) delta isolates the
*run* cost on top of pure transpilation. (1)-(3) are pure in-process cold-starts
(no docker); (4) measures the latency to spin the tux container and load the
tmuxp session, and is auto-skipped when no docker daemon is available.

Benchmarks (1)-(3) are **parametrized** across two axes:

  * make version -- the host's native ``make``, plus pinned versions run inside
    stock containers (``debian:bookworm-slim`` = make 4.3, ``alpine:3.21.2`` =
    make 4.4.x). The container envs are ``needs_docker`` and build a tiny deps
    image once per session; their per-sample timing includes a ~constant
    docker-run overhead, so read DELTAS *across make versions at the same mode*,
    not absolute container-vs-host numbers. (This axis exists because GNU make
    4.4 re-expands exported ``$(shell)`` vars per subshell -- see the
    ``compose.mk`` probe comments -- so it is the canary for that class of
    regression.)
  * install mode -- ``local`` (vendored ``./compose.mk`` in the workspace) vs
    ``global`` (``compose.mk`` outside the workspace, invoked by absolute path /
    on PATH, with ``DOCKER_HOST_WORKSPACE`` set), which exercise compose.mk's two
    self-path branches.

Unlike the rest of the suite, these run with compose.mk's *real* defaults
(supervisor + hooks ON) -- that's the latency a user actually pays on a cold
invocation. Each sample asserts a clean exit (rc==0); we print
min/median/mean/max but assert no latency threshold (machine-dependent, so this
is a report, not a PR gate).
"""

import functools
import json
import os
import re
import shutil
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

# Sample count per benchmark (the task asks for 10; override for ad-hoc runs).
SAMPLES = int(os.environ.get("CMK_PERF_SAMPLES", "10"))

# Where time-stamped result JSON is persisted (one file per perf run). Mirrors the
# coverage convention (dot-prefixed, under tests/, gitignored). Override the dir with
# CMK_PERF_RESULTS_DIR. Each `_bench` appends a structured record to `_PERF_RESULTS`,
# and a session finalizer writes them all to `<dir>/perf-<UTC-timestamp>.json`.
PERF_RESULTS_DIR = Path(
  os.environ.get("CMK_PERF_RESULTS_DIR", str(REPO / "tests" / ".perf-results"))
)
_PERF_RESULTS = []

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

# Parametrization axes for the in-process benchmarks ------------------------
# make environments: (label, base-image-or-None). None => the host's native make;
# a base image => run inside a tiny deps container built from it (needs_docker).
MAKE_ENVS = [
  pytest.param(("host", None), id="host"),
  pytest.param(
    ("deb", "debian:bookworm-slim"),
    id="deb-make4.3",
    marks=pytest.mark.needs_docker,
  ),
  pytest.param(
    ("alp", "alpine:3.21.2"),
    id="alp-make4.4",
    marks=pytest.mark.needs_docker,
  ),
]
INSTALL_MODES = ["local", "global"]


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
  """Print a one-line summary (visible with pytest ``-s`` / ``--capture=no``) AND
  record a structured result for the session JSON (see `_persist_perf_results`)."""
  rec = {
    "label": label,
    "n": len(times),
    "min": min(times),
    "median": statistics.median(times),
    "mean": statistics.fmean(times),
    "max": max(times),
    "times": times,
  }
  _PERF_RESULTS.append(rec)
  print(
    f"\n[perf] {label}: n={rec['n']} "
    f"min={rec['min']:.3f}s "
    f"median={rec['median']:.3f}s "
    f"mean={rec['mean']:.3f}s "
    f"max={rec['max']:.3f}s"
  )


@pytest.fixture(scope="session", autouse=True)
def _persist_perf_results():
  """Persist every benchmark's result to a time-stamped JSON on completion.

  Writes ``<PERF_RESULTS_DIR>/perf-<UTC-timestamp>.json`` (one file per run) iff any
  benchmark actually ran, so a deselected/empty perf session leaves nothing behind.
  These files are gitignored.
  """
  yield
  if not _PERF_RESULTS:
    return
  now = datetime.now(timezone.utc)
  PERF_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
  path = PERF_RESULTS_DIR / f"perf-{now.strftime('%Y%m%dT%H%M%SZ')}.json"
  payload = {
    "timestamp": now.isoformat(),
    "host_make": _make_version(),
    "samples": SAMPLES,
    "results": _PERF_RESULTS,
  }
  path.write_text(json.dumps(payload, indent=2) + "\n")
  print(f"\n[perf] wrote {len(_PERF_RESULTS)} result(s) -> {path}")


@functools.lru_cache(maxsize=None)
def _make_version(image=None):
  """`GNU Make X.Y` version for the host (image=None) or a built image tag."""
  cmd = ["make", "--version"]
  if image is not None:
    cmd = ["docker", "run", "--rm", image, "make", "--version"]
  try:
    out = subprocess.run(
      cmd, capture_output=True, text=True, timeout=120
    ).stdout
    m = re.search(r"GNU Make (\S+)", out)
    return m.group(1) if m else "?"
  except Exception:
    return "?"


@pytest.fixture(scope="session")
def perf_image():
  """Build (once per session, on demand) a tiny deps image for a container
  make-env. compose.mk's runtime needs: bash, GNU make/awk, jq, coreutils."""
  cache = {}

  def build(label, base):
    if label in cache:
      return cache[label]
    if "alpine" in base:
      df = f"FROM {base}\nRUN apk add --no-cache bash make jq gawk coreutils\n"
    else:
      df = (
        f"FROM {base}\nRUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive "
        "apt-get install -y -qq make bash jq gawk coreutils >/dev/null\n"
      )
    tag = f"cmkperf-{label}:test"
    r = subprocess.run(
      ["docker", "build", "-t", tag, "-"],
      input=df,
      text=True,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
    )
    if r.returncode != 0:
      pytest.skip(f"could not build perf image {tag}:\n{r.stdout[-1500:]}")
    cache[label] = tag
    return tag

  return build


def _runner(make_env, mode, tmp_path, perf_image):
  """Return a ``bench(name, args, ...)`` that runs ``compose.mk args`` for the
  given (make_env, install_mode), timing it via ``_bench``.

  install mode is realized by WHERE compose.mk lives: ``local`` -> a vendored
  copy in the (host-shared) workspace, run as ``./compose.mk``; ``global`` -> a
  copy outside the workspace, invoked by absolute path / on PATH with
  ``DOCKER_HOST_WORKSPACE`` pointed at the workspace.
  """
  label, image = make_env
  ws = tmp_path / "ws"
  ws.mkdir()

  if image is None:  # ---- native host make ----
    ver = _make_version()
    if mode == "local":
      shutil.copy(COMPOSE_MK, ws / "compose.mk")
      argv0, cwd, xenv = [str(ws / "compose.mk")], ws, {}
    else:  # global: compose.mk outside the workspace
      gbin = tmp_path / "bin"
      gbin.mkdir()
      shutil.copy(COMPOSE_MK, gbin / "compose.mk")
      argv0 = [str(gbin / "compose.mk")]
      cwd, xenv = ws, {"DOCKER_HOST_WORKSPACE": str(ws)}

    def bench(name, args, stdin=None, files=None, env=None, **kw):
      for n, c in (files or {}).items():
        (ws / n).write_text(c)
      _bench(
        f"{name} [host make {ver} / {mode}]",
        argv0 + args,
        cwd=cwd,
        env={**xenv, **(env or {})},
        stdin=stdin,
        **kw,
      )

    return bench

  # ---- pinned make inside a container ----
  tag = perf_image(label, image)
  ver = _make_version(tag)
  # identical-path workspace mount so any in-container path == host path.
  if mode == "local":
    shutil.copy(COMPOSE_MK, ws / "compose.mk")
    mounts, compose = ["-v", f"{ws}:{ws}"], "./compose.mk"
  else:  # global: bind compose.mk onto PATH, workspace has no vendored copy
    mounts = [
      "-v",
      f"{COMPOSE_MK}:/usr/local/bin/compose.mk:ro",
      "-v",
      f"{ws}:{ws}",
    ]
    compose = "compose.mk"

  def bench(name, args, stdin=None, files=None, env=None, **kw):
    for n, c in (files or {}).items():
      (ws / n).write_text(c)
    eflags = [
      "-e",
      "NO_COLOR=1",
      "-e",
      "TERM=dumb",
      "-e",
      f"DOCKER_HOST_WORKSPACE={ws}",
    ]
    for k, v in (env or {}).items():
      eflags += ["-e", f"{k}={v}"]
    cmd = f"cd {ws} && {compose} " + " ".join(args)
    argv = [
      "docker",
      "run",
      "--rm",
      "-i",
      *mounts,
      *eflags,
      tag,
      "sh",
      "-c",
      cmd,
    ]
    _bench(
      f"{name} [container make {ver} / {mode} (+docker-run overhead)]",
      argv,
      cwd=ws,
      stdin=stdin,
      **kw,
    )

  return bench


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_flux_ok_coldstart(make_env, install_mode, tmp_path, perf_image):
  """N cold-start samples of simple tool-mode ``compose.mk flux.ok``."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "flux.ok (tool-mode)", ["flux.ok"]
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_cmk_compile_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of pure CMK transpilation (``mk.compile``)."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "mk.compile (cmk transpile)", ["mk.compile"], stdin=SAMPLE_CMK
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_cmk_interpret_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of a CMK compile+interpret (``mk.interpret!``)."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "mk.interpret! (cmk compile+interpret)",
    ["mk.interpret!", "perf.cmk"],
    files={"perf.cmk": SAMPLE_CMK},
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

  Not in the make-version/install matrix above: its cost is dominated by the
  dockerized ``compose.mk:tux`` build + tmuxp load, and the make that matters
  inside is the tux image's own, not the host's. Measures the wall-clock to spin
  the container and load the tmuxp session -- the latency before the UI is
  interactive. Headless, so stdin is closed and success is the tmuxp ``Loaded
  workspace`` marker, NOT rc==0 (the final ``tmux attach`` fails without a tty).
  The tux image is built once up front so its one-time build cost is excluded
  from the samples; needs docker (auto-skipped otherwise). Invoked by the
  RELATIVE ``./compose.mk`` from the repo so the in-container ``make -f`` paths
  resolve via the /workspace mount.
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
