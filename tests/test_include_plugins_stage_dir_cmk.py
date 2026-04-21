"""include.plugins resolves every .cmk against the source prefix, not the stage dir.

Regression for a config-cascade defect: mk.unpack.kwargs writes results to the global
kwargs_prefix, and the .cmk resolution loop re-read it each pass.  Staging plugin one made a
re-entrant include with prefix set to the stage dir, clobbering that global, so plugin two was
resolved against the stage dir and reported missing.  Only bites when stage != source prefix
(default aliases both to .cmk) and only for the 2nd+ .cmk in one call, which is why the
one-plugin-per-test plugin suite never caught it.
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

SHEBANG = "#!/usr/bin/env -S ./compose.mk cmk compile\n"


def _run(tmp_path, goal, *, same_dir):
  # Two trivial .cmk plugins under a source prefix; stage points elsewhere (same_dir=False)
  # or at the prefix itself (same_dir=True, the benign default-aliased case).
  plugins = tmp_path / "plugins"
  plugins.mkdir()
  (plugins / "one.cmk").write_text(SHEBANG + "one.hi:; @echo ONE_LOADED\n")
  (plugins / "two.cmk").write_text(SHEBANG + "two.hi:; @echo TWO_LOADED\n")
  stage = plugins if same_dir else (tmp_path / "stage")
  mk = tmp_path / "wrap.mk"
  mk.write_text(
    f"include {COMPOSE}\n"
    f"$(call include.plugins, prefix={plugins} one.cmk two.cmk)\n"
    f"probe:; @echo BOTH_OK\n"
  )
  env = {**os.environ, "CMK_STAGE_DIR": str(stage), "NO_COLOR": "1"}
  r = subprocess.run(
    ["make", "-f", str(mk), goal],
    cwd=str(tmp_path),
    capture_output=True,
    text=True,
    errors="replace",
    env=env,
    timeout=180,
  )
  return r.stdout + r.stderr


def test_second_cmk_resolves_when_stage_differs_from_prefix(tmp_path):
  # The bug: plugin two was looked up in the stage dir and errored CMK_INCLUDE_MISSING.
  out = _run(tmp_path, "two.hi", same_dir=False)
  assert "CMK_INCLUDE_MISSING" not in out, out
  assert "TWO_LOADED" in out, out


def test_first_cmk_still_loads_with_separate_stage(tmp_path):
  # Plugin one (which triggers the clobber) must itself load fine too.
  out = _run(tmp_path, "one.hi", same_dir=False)
  assert "CMK_INCLUDE_MISSING" not in out, out
  assert "ONE_LOADED" in out, out


def test_control_stage_equals_prefix_still_works(tmp_path):
  # The default-aliased case (stage == source prefix) was never broken; guards the fix.
  out = _run(tmp_path, "two.hi", same_dir=True)
  assert "CMK_INCLUDE_MISSING" not in out, out
  assert "TWO_LOADED" in out, out
