"""Smoke tests: wrap the legacy shell scripts in tests/scripts/.

Each `tests/scripts/*.sh` is run and asserted to exit cleanly. For now we
only check the exit status - stdout/stderr are intentionally not asserted
(the scripts are exploratory smoke coverage, not golden output).

The scripts use repo-relative paths (`./compose.mk`, `./demos/...`), so they
run with cwd at the repo root. They need docker + assorted CLI tools, so they
carry the `needs_docker` gate and auto-skip when no daemon is reachable.
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = sorted((REPO / "tests" / "scripts").glob("*.sh"))

pytestmark = [pytest.mark.smoke, pytest.mark.needs_docker]


@pytest.mark.parametrize(
  "script",
  SCRIPTS,
  ids=[s.name for s in SCRIPTS],
)
def test_smoke_script(script):
  proc = subprocess.run(
    [str(script)],
    cwd=str(REPO),
    capture_output=True,
    text=True,
  )
  assert proc.returncode == 0, (
    f"{script.name} exited {proc.returncode}\n"
    f"--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}"
  )
