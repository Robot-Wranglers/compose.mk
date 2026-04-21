"""Tests for the user bootloader hook (CMK_BOOTLOADER).

compose.mk's supervisor aggregates "loaders" in `_mk.super.bootloader`; setting
CMK_BOOTLOADER to a file makes the supervisor `source` exactly that one user file FIRST -- at
boot, before the trampoline -- in the supervisor's own shell, so it sees pre-run state
($__argv__, $MAKE_SUPER) and may register an EXIT trap to reach the run's end ($__exit_code__ final).
This drives demos/user-bootloader.sh (prints a boot marker + an exit-trap line).  The
supervisor is required (CMK_SUPERVISOR=1), since the bootloader lives in the supervised
branch of the polyglot header.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
BOOTLOADER = REPO / "demos" / "user-bootloader.sh"
FILE_GOAL_BOOTLOADER = REPO / "demos" / "user-bootloader.mk"
SUP = {"CMK_SUPERVISOR": "1"}


def test_user_bootloader_is_sourced(cmk):
  # CMK_BOOTLOADER set -> sourced at boot (its marker appears BEFORE the target) and its EXIT
  # trap fires at the end, seeing the final exit code ($__exit_code__=0 for a clean flux.ok).
  r = cmk(
    "flux.ok", env={**SUP, "CMK_BOOTLOADER": str(BOOTLOADER)}, cwd=str(REPO)
  )
  assert r.ok, r.stderr
  assert "user-bootloader: boot" in r.stdout, r.stdout
  assert "user-bootloader: exit (code=0)" in r.stdout, r.stdout


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
  assert "succeeding as requested" not in (
    r.stdout + r.stderr
  )  # target never ran


def test_file_goal_bootloader_takes_over(cmk):
  # @<file>:<goal> execs `make -f <file> <goal>` -- a TARGET that TAKES OVER: its marker
  # appears, the invocation's own target (flux.ok) is SKIPPED, and the supervisor forwards
  # __argv__ (the goals) + CMK_TRAMP_MK (the make command) into the recipe.
  r = cmk(
    "flux.ok",
    env={**SUP, "CMK_BOOTLOADER": f"@{FILE_GOAL_BOOTLOADER}:user.tramp"},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "user-tramp: took over" in r.stdout, r.stdout
  assert "flux.ok" in r.stdout, r.stdout  # __argv__ forwarded (may be target-rewritten)
  assert "make=[make " in r.stdout, r.stdout  # CMK_TRAMP_MK forwarded
  # the takeover replaced the trampoline -> the real flux.ok never ran.
  assert "succeeding as requested" not in (r.stdout + r.stderr), r.stdout


# --- trampoline-backend selection (`CMK_TRAMPOLINE=<x>` -> exec <plugins>/<x>.loader.mk) ------
# The backend handoff is a CONVENTION-DRIVEN @file:goal: selecting a trampoline execs its
# `<plugins>/<x>.loader.mk : <x>.super.tramp` target (takeover), forwarding __argv__ +
# CMK_TRAMP_MK.  It is SKIPPED when CMK_TRAMPOLINE_ACTIVE is set -- the generic recursion
# guard that lets a backend's own hop sub-makes fall through to the bash tramp.  Driven by a
# throwaway FAKE loader so no elixir/docker (or the real beam backend) is needed.

_FAKE_LOADER = (
  "faketramp.super.tramp:\n"
  "\t@echo 'faketramp: took over goals=[$(__argv__)] make=[$(CMK_TRAMP_MK)]'\n"
)


def _fake_plugins(tmp_path):
  d = tmp_path / "plugins"
  d.mkdir(exist_ok=True)
  (d / "faketramp.loader.mk").write_text(_FAKE_LOADER)
  return str(d)


def test_trampoline_selection_takes_over(cmk, tmp_path):
  # CMK_TRAMPOLINE=faketramp -> the bootloader execs the loader.mk target: its marker appears,
  # the invocation's own target (flux.ok) is SKIPPED, and __argv__ + CMK_TRAMP_MK are forwarded.
  d = _fake_plugins(tmp_path)
  r = cmk(
    "flux.ok",
    env={**SUP, "CMK_TRAMPOLINE": "faketramp", "CMK_PLUGINS_DIR": d},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "faketramp: took over" in r.stdout, r.stdout
  assert "goals=[flux.ok]" in r.stdout, r.stdout  # __argv__ forwarded
  assert "make=[make " in r.stdout, r.stdout  # CMK_TRAMP_MK forwarded
  assert "succeeding as requested" not in (r.stdout + r.stderr), r.stdout


def test_trampoline_selection_active_guard_skips(cmk, tmp_path):
  # CMK_TRAMPOLINE_ACTIVE=1 (a takeover already active in this tree) -> selection is SKIPPED so
  # the run falls through to the bash tramp: no takeover marker, and the real flux.ok runs.
  d = _fake_plugins(tmp_path)
  r = cmk(
    "flux.ok",
    env={
      **SUP,
      "CMK_TRAMPOLINE": "faketramp",
      "CMK_PLUGINS_DIR": d,
      "CMK_TRAMPOLINE_ACTIVE": "1",
    },
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "faketramp: took over" not in r.stdout, r.stdout
  assert "succeeding as requested" in r.stderr, r.stderr  # bash tramp ran the real target


def test_bootloader_disabled_bypasses(cmk):
  # CMK_BOOTLOADER_DISABLED -> a yellow warning + the bootloader is bypassed ENTIRELY:
  # targets still run, but nothing is sourced (even a set CMK_BOOTLOADER is skipped).
  r = cmk(
    "flux.ok",
    env={
      **SUP,
      "CMK_BOOTLOADER_DISABLED": "1",
      "CMK_BOOTLOADER": str(BOOTLOADER),
    },
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "bootloader disabled" in r.stderr, r.stderr  # the warning
  assert "succeeding as requested" in r.stderr, r.stderr  # target still ran
  assert "user-bootloader" not in (
    r.stdout + r.stderr
  )  # bootloader fully bypassed


# --- hosted-partition pre-warm bootloader (`_cmk.prewarm.hosted`) -------------
# A BUILT-IN loader (always in the aggregator, not user-set) that materializes the
# HOSTED cache before the trampoline.  Tests redirect CMK_MODULES_DIR to a tmp dir so
# the cache does not land in the repo.


def _mods(tmp_path):
  # Pre-create the dir so the hosted-cache probe (reuse-if-exists-and-writable) keeps
  # the cache under tmp_path instead of falling back to the real ~/.cache (XDG).
  d = tmp_path / ".cmk"
  d.mkdir(exist_ok=True)
  return {"CMK_MODULES_DIR": str(d)}


def _hosted_cache(tmp_path):
  d = tmp_path / ".cmk"
  return sorted(d.glob(".tmp.hosted.*.mk")) if d.exists() else []


def test_hosted_prewarm_builds_cache(cmk, tmp_path):
  # Supervised run of a hosted target: the prewarm loader builds the cache, target runs.
  r = cmk("hosted.selftest", env={**SUP, **_mods(tmp_path)}, cwd=str(REPO))
  assert r.ok, r.stderr
  assert "hosted partition is live" in (r.stdout + r.stderr), r.stderr
  assert _hosted_cache(tmp_path), "prewarm did not build the hosted cache"


def test_hosted_prewarm_opt_out_still_correct(cmk, tmp_path):
  # CMK_HOSTED_PREWARM=0 disables the accelerator; the seed-level `-include` remaking
  # still binds the hosted target (one cold restart tolerated), so it must still run.
  r = cmk(
    "hosted.selftest",
    env={**SUP, **_mods(tmp_path), "CMK_HOSTED_PREWARM": "0"},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  assert "hosted partition is live" in (r.stdout + r.stderr), r.stderr


def test_hosted_prewarm_target_direct(cmk, tmp_path):
  # The make-side hook the loader calls: building it materializes the cache.
  r = cmk("mk.hosted.prewarm", env={**SUP, **_mods(tmp_path)}, cwd=str(REPO))
  assert r.ok, r.stderr
  assert _hosted_cache(tmp_path), "mk.hosted.prewarm did not build the cache"
