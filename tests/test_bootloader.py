"""Tests for the user bootloader hook (CMK_BOOTLOADER).

compose.mk's supervisor aggregates "loaders" in `_mk.supervisor.bootloader`; setting
CMK_BOOTLOADER to a file makes the supervisor `source` exactly that one user file FIRST -- at
boot, before the trampoline -- in the supervisor's own shell, so it sees pre-run state
($_targets, $MAKE_SUPER) and may register an EXIT trap to reach the run's end ($st final).
This drives demos/user-bootloader.sh (prints a boot marker + an exit-trap line).  The
supervisor is required (CMK_SUPERVISOR=1), since the bootloader lives in the supervised
branch of the polyglot header.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
BOOTLOADER = REPO / "demos" / "user-bootloader.sh"
SUP = {"CMK_SUPERVISOR": "1"}


def test_user_bootloader_is_sourced(cmk):
  # CMK_BOOTLOADER set -> sourced at boot (its marker appears BEFORE the target) and its EXIT
  # trap fires at the end, seeing the final exit code ($st=0 for a clean flux.ok).
  r = cmk("flux.ok", env={**SUP, "CMK_BOOTLOADER": str(BOOTLOADER)}, cwd=str(REPO))
  assert r.ok, r.stderr
  assert "user-bootloader: boot" in r.stdout, r.stdout
  assert "user-bootloader: exit (st=0)" in r.stdout, r.stdout


def test_no_bootloader_by_default(cmk):
  # Unset -> nothing extra is sourced.
  r = cmk("flux.ok", env={**SUP}, cwd=str(REPO))
  assert r.ok, r.stderr
  assert "user-bootloader" not in (r.stdout + r.stderr)


def test_missing_bootloader_is_fatal(cmk):
  # Set but nonexistent -> the existence assert fails the run loudly, and now FAST: before
  # the target runs (first-position bootloader).
  r = cmk(
    "flux.ok",
    env={**SUP, "CMK_BOOTLOADER": "/no/such/cmk-bootloader.sh"},
    cwd=str(REPO),
  )
  assert not r.ok
  assert "CMK_BOOTLOADER" in r.stderr and "not found" in r.stderr, r.stderr
  assert "succeeding as requested" not in (r.stdout + r.stderr)  # target never ran


def test_bootloader_disabled_bypasses(cmk):
  # CMK_BOOTLOADER_DISABLED -> a yellow warning + the bootloader is bypassed ENTIRELY:
  # targets still run, but nothing is sourced (even a set CMK_BOOTLOADER is skipped).
  r = cmk(
    "flux.ok",
    env={**SUP, "CMK_BOOTLOADER_DISABLED": "1", "CMK_BOOTLOADER": str(BOOTLOADER)},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "bootloader disabled" in r.stderr, r.stderr  # the warning
  assert "succeeding as requested" in r.stderr, r.stderr  # target still ran
  assert "user-bootloader" not in (r.stdout + r.stderr)  # bootloader fully bypassed
