"""Tests for the reflective __vm__ coroutine demo (demos/cmk/vm-coroutines.cmk).

The coroutine USED to be a `.cmk/coroutines.cmk` library plugin; it is now a DEMO
(demos/cmk/vm-coroutines.cmk) that is ALSO the canonical, importable home of `coroutines.demo`
-- libraries hold no demos, so other demos (overlay.cmk) import it via
`include.plugins, vm-coroutines.cmk prefix=demos/cmk`.  This file covers both faces: the demo run
directly, and the consumer-side import (the knob overrides a consumer applies, e.g. overlay).

Marked `unit` (fast, no docker) + `plugin` for a clean per-component slice.
"""

import json
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module, pytest.mark.covers_demo("vm-coroutines.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "vm-coroutines.cmk"


def _run_demo(*targets, timeout=60):
  # Run the demo file itself, supervised via `cmk run` from the repo root.
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def _run_consumer(tmp_path, body, *targets, timeout=60):
  # A minimal consumer that imports the demo as the shared coroutine source -- the same path
  # overlay.cmk uses -- run from the repo root so prefix=demos/cmk resolves against the real tree.
  prog = tmp_path / "consumer.cmk"
  prog.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(prog), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def test_demo_runs_through_phases():
  # The demo: coroutines.demo -> the reflective coroutine advances phase 0->1->2.
  r, out = _run_demo()
  assert r.returncode == 0, out
  assert "enter -> init phase=0" in out, out
  assert "resume -> step phase=1" in out, out
  assert "resume -> done phase=2" in out, out


def test_demo_dumps_persisted_reflective_env():
  # The demo defaults coroutines.dump_env := 1 -> the done phase prints the persisted reflective E,
  # which (under the exclude policy) reflects ONLY the coroutine's own `export phase`.
  r, out = _run_demo()
  assert r.returncode == 0, out
  m = re.search(r"persisted E = (\{.*\})", out)
  assert m, out
  assert json.loads(m.group(1)) == {"phase": "2"}, out


def test_consumer_import_wait_knob_paces_each_phase(tmp_path):
  # A consumer imports the demo via prefix and sets coroutines.wait -> each phase is preceded by
  # io.wait/<n> (the overlay/TUI pacing knob).
  r, out = _run_consumer(
    tmp_path,
    "$(call include.plugins, vm-coroutines.cmk prefix=demos/cmk)\n"
    "coroutines.wait := 1\n__main__: coroutines.demo\n",
  )
  assert r.returncode == 0, out
  assert "Waiting for 1 seconds" in out, out
  assert "resume -> done phase=2" in out, out


def test_consumer_can_clear_dump_env(tmp_path):
  # A consumer (e.g. overlay) clears coroutines.dump_env after import -> no persisted-E dump,
  # proving the demo's own default does not force itself on importers.
  r, out = _run_consumer(
    tmp_path,
    "$(call include.plugins, vm-coroutines.cmk prefix=demos/cmk)\n"
    "coroutines.dump_env :=\n__main__: coroutines.demo\n",
  )
  assert r.returncode == 0, out
  assert "resume -> done phase=2" in out, out
  assert "persisted E" not in out, out
