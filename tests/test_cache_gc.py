"""Behavior and cost pins for the parse-time cache sweep (`mk.cache.gc`).

The sweep ages out cache entries unused for `_CMK_CACHE_TTL` days, fired from a detached
`$(shell)` at parse time so it covers core both when executed and when a client pulls it
in with `include compose.mk`. The cost pin matters as much as the behavior pins: the hook
runs once per parse, not once per run, and only the `CMK_INTERNAL` gate holds it to
top-level parses. See `scratch/cache-unify-notes.md`. Docker-free.
"""

import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.cache]

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

ENV = {**os.environ, "NO_COLOR": "1", "TERM": "dumb", "GITHUB_ACTIONS": "false"}


def _cache(tmp_path, stamped):
  """A private cache root. With stamped set, the sweep sees a fresh stamp and no-ops."""
  root = tmp_path / "xdg"
  cache = root / "compose.mk"
  cache.mkdir(parents=True)
  if stamped:
    (cache / ".gc-stamp").touch()
  return root, cache


def _run(argv, env, timeout=120):
  return subprocess.run(
    argv, cwd=str(REPO), env=env, stdin=subprocess.DEVNULL,
    capture_output=True, text=True, errors="replace", timeout=timeout,
  )


def _count_tool(tool, argv, env, timeout=120):
  """Run argv with a log-then-exec shim for one tool first on PATH; return its exec count.

  Only `tool` is shimmed, so everything else resolves normally. The sweep detaches, so
  the log is polled until it stops growing rather than read at parent exit, which would
  undercount whatever had not been exec'd yet. Blind to absolute-path execs and shell
  builtins, same as the perf suite's wider census.
  """
  real = shutil.which(tool)
  if real is None or not os.path.isabs(real):
    pytest.skip(f"no absolute path for {tool}")
  tmp = tempfile.mkdtemp(suffix=".shim")
  try:
    log = Path(tmp) / "log"
    log.touch()
    shim = Path(tmp) / tool
    shim.write_text(f'#!/bin/sh\nprintf x >>"{log}"\nexec "{real}" "$@"\n')
    shim.chmod(0o755)
    subprocess.run(
      argv, cwd=str(REPO), stdin=subprocess.DEVNULL,
      env={**env, "PATH": tmp + os.pathsep + env.get("PATH", os.defpath)},
      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout,
    )
    seen, stable, deadline = -1, 0, time.time() + 10
    while stable < 3 and time.time() < deadline:
      time.sleep(0.1)
      now = len(log.read_text())
      stable = stable + 1 if now == seen else 0
      seen = now
    return seen
  finally:
    shutil.rmtree(tmp, ignore_errors=True)


def test_sweep_probes_at_most_twice_per_run(tmp_path):
  # A compile reparses core many times, so a lapsed gate is visible here but not on flux.ok.
  root, _ = _cache(tmp_path, stamped=True)
  prog = tmp_path / "probe.cmk"
  prog.write_text("import io\n__main__:\n\tio.print.banner\n")
  argv = [str(COMPOSE_MK), "cmk", "compile", str(prog)]
  base = {**ENV, "XDG_CACHE_HOME": str(root)}
  on = _count_tool("find", argv, {**base, "CMK_CACHE_GC": "1"})
  off = _count_tool("find", argv, {**base, "CMK_CACHE_GC": "0"})
  assert on - off <= 2, (
    f"the parse-time sweep probed {on - off} times in one run (expected at most 2). "
    "The CMK_INTERNAL gate probably stopped holding, so nested parses now fire it too."
  )


def test_sweep_is_disablable(tmp_path):
  # The knob is the escape hatch, so it has to actually suppress the hook.
  root, cache = _cache(tmp_path, stamped=False)
  r = _run([str(COMPOSE_MK), "flux.ok"],
           {**ENV, "XDG_CACHE_HOME": str(root), "CMK_CACHE_GC": "0"})
  assert r.returncode == 0, r.stderr[-1500:]
  assert not (cache / ".gc-stamp").exists(), "sweep ran with CMK_CACHE_GC=0"


def test_sweep_evicts_unused_and_spares_fresh(tmp_path):
  # Age is last-use, not creation, and a non-cache name like `bin` is out of scope.
  root, cache = _cache(tmp_path, stamped=False)
  (cache / "bin").mkdir()
  stale, fresh = cache / "0000000001", cache / "0000000002"
  for d in (stale, fresh):
    d.mkdir()
  old = time.time() - 60 * 60 * 24 * 30
  os.utime(stale, (old, old))
  r = _run([str(COMPOSE_MK), "mk.cache.gc"],
           {**ENV, "XDG_CACHE_HOME": str(root), "force": "1"})
  assert r.returncode == 0, r.stderr[-1500:]
  assert not stale.exists(), "an entry unused for 30 days survived the sweep"
  assert fresh.exists(), "a freshly used entry was evicted"
  assert (cache / "bin").exists(), "the sweep touched a non-cache directory"


def test_sweep_stamp_guards_repeat_runs(tmp_path):
  # Without the daily stamp the sweep would re-scan every root on every invocation.
  root, cache = _cache(tmp_path, stamped=False)
  stale = cache / "0000000001"
  stale.mkdir()
  old = time.time() - 60 * 60 * 24 * 30
  os.utime(stale, (old, old))
  env = {**ENV, "XDG_CACHE_HOME": str(root)}
  assert _run([str(COMPOSE_MK), "mk.cache.gc"], env).returncode == 0
  assert (cache / ".gc-stamp").exists(), "the sweep did not stamp"
  second = cache / "0000000002"
  second.mkdir()
  os.utime(second, (old, old))
  assert _run([str(COMPOSE_MK), "mk.cache.gc"], env).returncode == 0
  assert second.exists(), "a same-day repeat swept again instead of honoring the stamp"
