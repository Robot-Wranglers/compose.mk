"""Plugin suite: `coroutines.cmk` -- the reusable reflective __vm__ coroutine.

Dedicated BEHAVIOR coverage for the `.cmk/coroutines.cmk` plugin (the shared coroutine extracted
from demos/cmk/overlay.cmk + demos/cmk/vm-coroutines.cmk, which are now thin consumers).  This
file exercises the PLUGIN directly via a minimal in-tmp consumer program, independent of either
demo.  Marked both `unit` (fast, no docker) and `plugin`, so `tox -e plugin` gets a clean
per-plugin slice while the fast `unit` slice still covers it.

(Pure load -- "every shipped plugin imports + exposes a public symbol" -- lives in test_plugins.py;
the consumer-side coverage lives in test_overlay_cmk.py / test_vm_reflective.py.)
"""

import json
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, body, *targets, timeout=60):
  # A minimal consumer that imports the plugin, run supervised via `cmk run` from the repo root so
  # `include.plugins, coroutines.cmk` resolves against the real .cmk/ (CMK_PLUGINS_DIR default).
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


def test_coroutine_runs_through_phases(tmp_path):
  # The bare plugin: import + run coroutines.demo -> the reflective coroutine advances phase 0->1->2.
  r, out = _run(tmp_path, "$(call include.plugins, coroutines.cmk)\n__main__: coroutines.demo\n")
  assert r.returncode == 0, out
  assert "enter -> init phase=0" in out, out
  assert "resume -> step phase=1" in out, out
  assert "resume -> done phase=2" in out, out


def test_dump_env_knob_prints_persisted_reflective_env(tmp_path):
  # coroutines.dump_env -> the done phase prints the persisted reflective E, which (under the
  # plugin's exclude policy) reflects ONLY the coroutine's own `export phase`.
  r, out = _run(
    tmp_path,
    "$(call include.plugins, coroutines.cmk)\ncoroutines.dump_env := 1\n__main__: coroutines.demo\n",
  )
  assert r.returncode == 0, out
  m = re.search(r"persisted E = (\{.*\})", out)
  assert m, out
  assert json.loads(m.group(1)) == {"phase": "2"}, out


def test_wait_knob_paces_each_phase(tmp_path):
  # coroutines.wait -> each phase is preceded by io.wait/<n> (the overlay/TUI pacing knob).
  r, out = _run(
    tmp_path,
    "$(call include.plugins, coroutines.cmk)\ncoroutines.wait := 1\n__main__: coroutines.demo\n",
  )
  assert r.returncode == 0, out
  assert "Waiting for 1 seconds" in out, out
  assert "resume -> done phase=2" in out, out


def test_default_is_quiet_no_pacing_no_dump(tmp_path):
  # With neither knob set, there is no io.wait pacing and no persisted-E dump.
  r, out = _run(tmp_path, "$(call include.plugins, coroutines.cmk)\n__main__: coroutines.demo\n")
  assert r.returncode == 0, out
  assert "Waiting for" not in out, out
  assert "persisted E" not in out, out
