"""Cold-start performance benchmark for compose.mk (report-only).

Opt-in: **not gated on push/PR**. Runs on-demand via the Perf Tests workflow
(``.github/workflows/perf-tests.yml``); locally via ``tox -e perf-test``
(or ``make perf-test``). Measures wall-clock *cold-start* (a fresh process per
sample) over N samples (default 10, override with ``CMK_PERF_SAMPLES``) for a few
representative usages:

  1. simple tool-mode:        ``compose.mk flux.ok``
  2. CMK compile (transpile): ``compose.mk mk.compile`` (source on stdin)
  3. CMK compile+interpret:   ``compose.mk mk.interpret! <file>``
  4. namespace reflection:    ``compose.mk mk.parse`` (native awk+jq over the file)
  5. cmk subcommand dispatch: ``compose.mk cmk compile`` (the `cmk <sub>` CLI tax)
  6. banana-heavy compile:    ``compose.mk mk.compile`` (BANANA_CMK, all stages)
  7. shell completion:        ``compose.mk cmk cli complete``
  8. headless TUI bring-up:   ``./compose.mk tux.open/...`` (needs docker)
  9. cmk run (compile+run):   ``compose.mk cmk run <file>`` (the full user path)
 10. CMK_LANG bypass:         ``cmk run`` hosted (default) vs ``CMK_LANG=0`` lean

(9) is the headline end-user path (compile + interpret + supervisor) reached
through the ``cmk`` CLI. (10) is host-only and isolates the ``__hosted__``
partition-bypass win: the same ``cmk run`` with the CMK-lang partition loaded
(default) vs bypassed (``CMK_LANG=0``, the seed-only slice); its HOSTED-minus-LEAN
delta -- in wall-clock and in the subprocess count -- is the per-run cost of the
hosted ``-include`` across the run's reparses.

(2) and (3) share the same CMK source, so the (3)-vs-(2) delta isolates the
*run* cost on top of pure transpilation; (6)-vs-(2) isolates the per-construct
compiler-stage cost (same target, banana-heavy vs trivial source); (5)-vs-(2)
isolates the `cmk` subcommand-supervisor dispatch tax over the raw target. (4)
and (7) are the reflection/discovery hotpaths (help, completion, tab-complete)
that share the native mk.parse scan. (1)-(7) are pure in-process cold-starts
(no docker); (8) measures the latency to spin the tux container and load the
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

Alongside wall-clock, the host-make benchmarks also record a **subprocess count**:
one extra pass per benchmark is run under ``strace -f -e trace=execve``, counting
every program image the invocation launches (sub-makes, shells, awk, jq, ...) and
bucketing it by program name. This is machine-independent (unlike time) and is the
cleanest signal for regressions like "cold boot now forks make three times". It is
recorded per-benchmark in the JSON (``exec_total`` / ``exec_by_prog``) and printed
inline; it is skipped for the container make-envs (no strace in the deps image) and
when strace is unavailable (graceful -- the field is simply omitted).
"""

import functools
import json
import os
import re
import shutil
import statistics
import subprocess
import tempfile
import time
from collections import Counter
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

# A minimal seed-only program for the `cmk run` benchmarks: its __main__ is a
# pure-seed target (flux.ok), so the run cost is the compile+interpret+supervisor
# scaffolding itself, not user work -- the apples-to-apples base for the CMK_LANG
# hosted-vs-lean comparison (a hosted-using __main__ would keep hosted regardless).
CMK_RUN_CMK = "__main__: flux.ok\n"

# A banana-heavy CMK source: exercises the actual compiler STAGES (sugar bracket
# `[| |]`, recipe-level lambda-lift `(| |) in host.native.sh`, `<-` capture, and callform
# dispatch `this.foo`) rather than the near-trivial SAMPLE_CMK. Compiling this vs
# SAMPLE_CMK isolates the per-construct compiler cost from fixed transpile overhead.
# Self-contained (no `import`/`open`) so it compiles from a bare workspace.
BANANA_CMK = (
  "greet[| hello=world |]\n"
  "foo:\n"
  "\t(| echo hi |) in host.native.sh\n"
  "\tx <- (| printf data |)\n"
  "bar:\n"
  "\tthis.foo\n"
  "__main__: foo bar\n"
)

# Self-desugar benchmark: K structurally-identical class bodies differing ONLY in
# the self token. `self.` exercises the desugar path (a "transpilation in
# miniature": bare `self` / `self.X` -> the `${self}` ref at stamp time); `${self}.`
# is the explicit control that skips it. The BARE-minus-EXPLICIT delta isolates the
# desugar cost -- and its subprocess count exposes the per-body forks (the desugar
# runs once per body per re-parse pass) -- so it is the apples-to-apples number for
# comparing desugar implementations (the current sed stage vs a pure-make rewrite).
_SELF_CLASSES = 20


def _self_desugar_source(token, read):
  cls = [
    f"cmk.class k{i}(|\n"
    f"  {token}a := A{i}\n"
    f"  {token}b := B{i}\n"
    f"  {token}show:; @printf 'v=%s' '{read}'\n"
    f"|)\nk{i} n{i}(| |)"
    for i in range(_SELF_CLASSES)
  ]
  goals = " ".join(f"n{i}.show" for i in range(_SELF_CLASSES))
  return "from cmk import class\n" + "\n".join(cls) + f"\n__main__: {goals}\n"


SELF_BARE_CMK = _self_desugar_source("self.", "self.a")
SELF_EXPLICIT_CMK = _self_desugar_source("${self}.", "$(${self}.a)")

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


@functools.lru_cache(maxsize=1)
def _strace_available():
  """True iff a usable `strace` is on PATH (subprocess counting is best-effort)."""
  return shutil.which("strace") is not None


# A successful execve strace line ends in `= 0`; capture the exec'd program path.
_EXECVE_PATH = re.compile(r'execve\("([^"]*)"')
_EXECVE_OK = re.compile(r"=\s*0\s*$")


def _count_execs(argv, cwd, env, stdin=None, timeout=120):
  """Run ``argv`` once under strace; return ``(total, Counter{prog: n})``.

  Counts successful ``execve(2)`` across the whole process tree (``-f``) -- i.e.
  every program image the invocation actually launches (the top make, its
  sub-makes, shells, awk/gawk, jq, cat, ...). Failed execs (a shell probing
  ``$PATH``) end in ``-1`` and are ignored. Returns ``(None, None)`` when strace
  is unavailable or errors, so the caller records "not measured" without failing
  the perf run. This is a SEPARATE pass from the timed samples (strace's ptrace
  overhead would pollute the wall-clock numbers), run once per benchmark.
  """
  if not _strace_available():
    return None, None
  fd, trace_path = tempfile.mkstemp(suffix=".strace")
  os.close(fd)
  try:
    subprocess.run(
      ["strace", "-f", "-qq", "-e", "trace=execve", "-o", trace_path, *argv],
      cwd=str(cwd),
      env=env,
      input=stdin,
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
      text=True,
      timeout=timeout,
    )
    counts = Counter()
    for line in Path(trace_path).read_text(errors="replace").splitlines():
      if not _EXECVE_OK.search(line):
        continue
      m = _EXECVE_PATH.search(line)
      if m:
        counts[os.path.basename(m.group(1))] += 1
    return sum(counts.values()), counts
  except Exception:
    return None, None
  finally:
    try:
      os.unlink(trace_path)
    except OSError:
      pass


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
  count_procs=False,
):
  """Run ``argv`` ``samples`` times from ``cwd``, timing each cold start.

  Success per sample is ``rc == 0`` by default; pass ``marker`` to instead
  require that substring in the combined output and ignore the exit code -- for
  flows that legitimately end nonzero headless (e.g. a TUI whose final
  ``tmux attach`` fails without a tty). ``pre`` (if given) is called before each
  sample, OUTSIDE the timed region -- used to reset shared state so every sample
  is a genuine cold start.

  ``count_procs`` adds one extra, un-timed pass under strace to record how many
  subprocesses the invocation spawns (see `_count_execs`); best-effort, so it is
  a no-op where strace is missing. ``pre`` is honored for it too, so the counted
  pass is as cold as the timed samples.
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
  exec_total, exec_by = None, None
  if count_procs:
    if pre is not None:
      pre()  # keep the counted pass as cold as the timed samples
    exec_total, exec_by = _count_execs(argv, cwd, merged, stdin, timeout)
  _report(label, times, exec_total, exec_by)
  return times


def _report(label, times, exec_total=None, exec_by=None):
  """Print a one-line summary (visible with pytest ``-s`` / ``--capture=no``) AND
  record a structured result for the session JSON (see `_persist_perf_results`).

  When ``exec_total`` is provided, the subprocess count (and its per-program
  breakdown, largest first) is both recorded and printed on a second line."""
  rec = {
    "label": label,
    "n": len(times),
    "min": min(times),
    "median": statistics.median(times),
    "mean": statistics.fmean(times),
    "max": max(times),
    "times": times,
  }
  if exec_total is not None:
    by_prog = dict(sorted(exec_by.items(), key=lambda kv: (-kv[1], kv[0])))
    rec["exec_total"] = exec_total
    rec["exec_by_prog"] = by_prog
  _PERF_RESULTS.append(rec)
  print(
    f"\n[perf] {label}: n={rec['n']} "
    f"min={rec['min']:.3f}s "
    f"median={rec['median']:.3f}s "
    f"mean={rec['mean']:.3f}s "
    f"max={rec['max']:.3f}s"
  )
  if exec_total is not None:
    top = ", ".join(f"{k}={v}" for k, v in list(by_prog.items())[:8])
    print(f"[perf]   └ subprocesses={exec_total} ({top})")


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
        count_procs=True,  # host-only: strace the subprocess tree
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
def test_perf_hosted_partition_coldstart(tmp_path):
  """HOSTED partition cost on the plain-`include compose.mk` path (host make only).

  Quantifies the two costs the partition adds to a vanilla include:
    * COLD  -- cache cleared each sample -> full lower + one makefile-remaking restart;
    * WARM  -- cache present -> just the parse-time region-hash + `-include`.
  The COLD-vs-WARM delta is the compile+restart cost; the WARM number vs a plain
  target is the per-parse region-hash tax (the go/no-go signal from the plan).
  """
  ws = tmp_path / "ws"
  ws.mkdir()
  # Pre-create ./.cmk so the cache lands HERE (project-local), not the user XDG cache
  # -- otherwise `_clear_cache` below clears nothing and COLD would measure WARM.
  (ws / ".cmk").mkdir()
  shutil.copy(COMPOSE_MK, ws / "compose.mk")
  (ws / "Makefile").write_text(
    "include compose.mk\n__main__: hosted.selftest\n"
  )

  def _clear_cache():
    d = ws / ".cmk"
    if d.exists():
      for p in d.glob(".tmp.hosted.*"):
        p.unlink()

  # COLD: force a genuine rebuild + restart every sample. The subprocess count
  # here is the cold-boot process tree (full lower + the makefile-remaking restart).
  _bench(
    "hosted.selftest [host / COLD (rebuild+restart)]",
    ["make", "hosted.selftest"],
    cwd=ws,
    pre=_clear_cache,
    count_procs=True,
  )
  # WARM: cache already built (populated by the cold run above); its subprocess
  # count is the second-parse tree (region-hash + `-include`, no rebuild).
  _bench(
    "hosted.selftest [host / WARM (cached)]",
    ["make", "hosted.selftest"],
    cwd=ws,
    count_procs=True,
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


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_cmk_run_coldstart(make_env, install_mode, tmp_path, perf_image):
  """N cold-start samples of the full ``cmk run <file>`` user path.

  The headline end-user invocation: compile the program, then interpret+run it
  under the supervisor -- reached through the ``cmk`` subcommand CLI. Distinct
  from `test_perf_cmk_interpret_coldstart` (raw ``mk.interpret!``) in that it
  pays the ``cmk`` dispatch + full run-mode boot on top."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "cmk run (compile+interpret+supervise)",
    ["cmk", "run", "run.cmk"],
    files={"run.cmk": CMK_RUN_CMK},
  )


@pytest.mark.perf
def test_perf_cmk_lang_mode_coldstart(tmp_path):
  """``cmk run`` cold-start: hosted (default) vs ``CMK_LANG=0`` lean (host only).

  Two runs of the SAME seed-only program differing only in whether the
  ``__hosted__`` CMK-lang partition is loaded: default (hosted) vs ``CMK_LANG=0``
  (the seed-only bypass). The HOSTED-minus-LEAN wall-clock delta -- and its
  subprocess-count delta -- is the per-run cost the hosted ``-include`` adds
  across the run's reparses (the Lever-3 headroom). Host make only (a
  compose.mk-internal path)."""
  ws = tmp_path / "ws"
  ws.mkdir()
  shutil.copy(COMPOSE_MK, ws / "compose.mk")
  (ws / "run.cmk").write_text(CMK_RUN_CMK)
  ver = _make_version()
  compose = str(ws / "compose.mk")
  _bench(
    f"cmk run [host make {ver} / HOSTED (default)]",
    [compose, "cmk", "run", "run.cmk"],
    cwd=ws,
    count_procs=True,
  )
  _bench(
    f"cmk run [host make {ver} / LEAN (CMK_LANG=0)]",
    [compose, "cmk", "run", "run.cmk"],
    cwd=ws,
    env={"CMK_LANG": "0"},
    count_procs=True,
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_reflection_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of native namespace reflection (``mk.parse``).

  The awk+jq whole-file parse behind ``help`` / completion / ``mk.targets`` --
  the discovery hotpath, distinct from transpilation (it reads the makefile's
  target/doc structure rather than lowering CMK)."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "mk.parse (namespace reflection)", ["mk.parse"]
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_cmk_subcommand_dispatch_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of the ``cmk`` subcommand CLI (``cmk compile``).

  Same transpile as `test_perf_cmk_compile_coldstart`, but reached through the
  ``cmk <sub>`` subcommand supervisor rather than the raw ``mk.compile`` target
  -- so the delta between the two is the subcommand-dispatch tax a user pays for
  typing ``cmk compile`` instead of the underlying target."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "cmk compile (subcommand dispatch)", ["cmk", "compile"], stdin=SAMPLE_CMK
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_banana_compile_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of compiling a BANANA-heavy source (``mk.compile``).

  Same target as `test_perf_cmk_compile_coldstart` but a source that exercises
  the sugar/lambda-lift/banana/callform stages (vs the near-trivial SAMPLE_CMK),
  so the delta isolates the per-construct compiler-stage cost from the fixed
  transpile overhead."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "mk.compile (banana-heavy source)", ["mk.compile"], stdin=BANANA_CMK
  )


@pytest.mark.perf
@pytest.mark.parametrize("install_mode", INSTALL_MODES)
@pytest.mark.parametrize("make_env", MAKE_ENVS)
def test_perf_completion_coldstart(
  make_env, install_mode, tmp_path, perf_image
):
  """N cold-start samples of shell-completion generation (``cmk cli complete``).

  The interactive hotpath a user's shell invokes on every TAB: emits a
  self-contained completion script off the same native mk.parse scan as
  reflection. Report-only; latency here is felt directly at the prompt."""
  _runner(make_env, install_mode, tmp_path, perf_image)(
    "cmk cli complete (shell completion)", ["cmk", "cli", "complete"]
  )


@pytest.mark.perf
def test_perf_self_desugar_coldstart(tmp_path):
  """N cold-start samples of the `self.` desugar path (host make only).

  The per-class-body "transpilation in miniature" that compiles bare `self` /
  `self.X` -> the `${self}` ref at instance-stamp time. Benches two structurally
  identical K-class sources differing ONLY in the self token: `self.` (desugar
  path) vs `${self}.` (explicit control that skips it). The BARE-minus-EXPLICIT
  wall-clock delta isolates the desugar cost, and the subprocess count exposes
  its per-body forks (the sed stage, re-run each re-parse pass) -- the
  apples-to-apples number for comparing desugar impls (sed vs a pure-make
  rewrite). Host make only (a compose.mk-internal path); CMK_SUPERVISOR on so
  interpret!'s yield-epilogue exits clean."""
  ws = tmp_path / "ws"
  ws.mkdir()
  shutil.copy(COMPOSE_MK, ws / "compose.mk")
  (ws / "bare.cmk").write_text(SELF_BARE_CMK)
  (ws / "explicit.cmk").write_text(SELF_EXPLICIT_CMK)
  ver = _make_version()
  env = {"CMK_SUPERVISOR": "1"}
  compose = str(ws / "compose.mk")
  _bench(
    f"self-desugar BARE [host make {ver} / {_SELF_CLASSES} classes]",
    [compose, "mk.interpret!", "bare.cmk"],
    cwd=ws,
    env=env,
    count_procs=True,
  )
  _bench(
    f"self-desugar EXPLICIT control [host make {ver} / {_SELF_CLASSES} classes]",
    [compose, "mk.interpret!", "explicit.cmk"],
    cwd=ws,
    env=env,
    count_procs=True,
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
