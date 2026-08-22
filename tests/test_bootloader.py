"""Tests for the user bootloader hook (CMK_BOOTLOADER).

compose.mk's supervisor aggregates "loaders" in `_mk.super.bootloader`; setting
CMK_BOOTLOADER to a file makes the supervisor `source` exactly that one user file FIRST -- at
boot, before the trampoline -- in the supervisor's own shell, so it sees pre-run state
($__argv__, $MAKE_SUPER) and may register an EXIT trap to reach the run's end ($__exit_code__ final).
This drives demos/user-bootloader.sh (prints a boot marker + an exit-trap line).  The
supervisor is required (CMK_SUPERVISOR=1), since the bootloader lives in the supervised
branch of the polyglot header.
"""

import os
import shutil
import subprocess
import sys
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
  assert "flux.ok" in r.stdout, (
    r.stdout
  )  # __argv__ forwarded (may be target-rewritten)
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
  assert "succeeding as requested" in r.stderr, (
    r.stderr
  )  # bash tramp ran the real target


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


VERSION_GUARD_LIST = "3.% 4.0 4.0.% 4.1 4.1.%"


def test_make_version_floor_fires_with_named_error(tmp_path):
  """Hermetic wiring check for the parse-time version floor.

  Widens the guard's filter so it fires under the CURRENT make, then asserts
  the failure names the requirement.  This also guards the guard's placement:
  if the gate ever drifts below the first modern construct, old-make users
  would see a bare missing-separator error and this test's doctored copy
  would too."""
  src = (REPO / "compose.mk").read_text()
  assert VERSION_GUARD_LIST in src, "floor filter moved; update this test"
  doctored = tmp_path / "compose.doctored.mk"
  doctored.write_text(src.replace(VERSION_GUARD_LIST, "%", 1))
  r = subprocess.run(
    ["make", "-f", str(doctored), "flux.ok"],
    capture_output=True,
    text=True,
    cwd=str(tmp_path),
    timeout=120,
  )
  assert r.returncode != 0
  assert "needs GNU make >= 4.2" in r.stderr, r.stderr[-800:]
  assert "missing separator" not in r.stderr, r.stderr[-800:]


@pytest.mark.needs_docker
def test_make_version_floor_real_old_make(tmp_path):
  """First-contact UX on Apple's frozen toolchain: real GNU make 3.81 (via a
  debian squeeze image) must fail the parse with the version story, not the
  raw missing-separator error it produced before the guard existed."""
  df = (
    "FROM debian/eol:squeeze\n"
    "RUN apt-get update -qq >/dev/null 2>&1 || true; "
    "apt-get install -y --force-yes -qq make >/dev/null 2>&1\n"
  )
  tag = "cmk-test-make381:latest"
  b = subprocess.run(
    ["docker", "build", "-q", "-t", tag, "-"],
    input=df,
    capture_output=True,
    text=True,
  )
  if b.returncode != 0:
    pytest.skip(f"cannot build the make-3.81 image: {b.stderr[-300:]}")
  r = subprocess.run(
    [
      "docker",
      "run",
      "--rm",
      "-v",
      f"{REPO}/compose.mk:/work/compose.mk:ro",
      "-w",
      "/work",
      tag,
      "make",
      "-f",
      "compose.mk",
      "flux.ok",
    ],
    capture_output=True,
    text=True,
    timeout=300,
  )
  assert r.returncode != 0
  assert "needs GNU make >= 4.2" in r.stderr, r.stderr[-800:]
  assert "3.81" in r.stderr, r.stderr[-800:]


def test_awk_flavor_gate_rejects_unknown_dialect(cmk, tmp_path):
  """Hermetic check of the compiler's awk gate: a PATH-first awk reporting an
  unknown version banner must make any compile fail loudly, naming the
  supported dialect set, before emitting garbage.  The four supported
  dialects (gawk, mawk, busybox, one-true-awk) are pinned separately by
  test_awk_dialects.py."""
  real = shutil.which("awk")
  shim = tmp_path / "bin"
  shim.mkdir()
  fake = shim / "awk"
  fake.write_text(
    "#!/bin/sh\n"
    'case "$1" in --version) echo "gsak 0.1 (unsupported)"; exit 0;; esac\n'
    f'exec "{real}" "$@"\n'
  )
  fake.chmod(0o755)
  path = f"{shim}:{os.environ['PATH']}"
  r = cmk("mk.compile", stdin="x:; @printf X\n", env={"PATH": path})
  assert not r.ok
  assert "supports GNU awk" in (r.stdout + r.stderr), r.stderr[-800:]


@pytest.mark.skipif(
  sys.platform != "darwin", reason="needs the real BSD sed at /usr/bin/sed"
)
def test_bsd_sed_is_not_a_silent_noop(cmk, tmp_path):
  """The stock-macOS sed pin, sibling of the make floor and the awk gate:
  with BSD sed PATH-first, a supervised run must either work or fail
  loudly; the header extraction is BSD-compatible, so it works."""
  shim = tmp_path / "bin"
  shim.mkdir()
  (shim / "sed").symlink_to("/usr/bin/sed")
  path = f"{shim}:{os.environ['PATH']}"
  r = cmk("flux.ok", env={**SUP, "PATH": path}, cwd=str(REPO))
  ran = r.ok and "succeeding as requested" in (r.stdout + r.stderr)
  failed_loudly = not r.ok and (r.stdout + r.stderr).strip()
  assert ran or failed_loudly, (r.returncode, r.stdout, r.stderr)


@pytest.mark.needs_docker
def test_busybox_awk_runs_hosted_and_lean(tmp_path):
  """The busybox-awk first-contact pin, post dialect-port: without gawk, both
  the hosted and the lean (CMK_LANG=0) run paths must now SUCCEED.  Before
  the port this environment compiled garbage and the lean path exited 0
  after the stub main swallowed it, the worst degraded-toolchain behavior;
  the dialect matrix in test_awk_dialects.py holds the deeper invariant."""
  df = "FROM alpine:3.21.2\nRUN apk add --no-cache bash make jq\n"
  tag = "cmk-test-nogawk:latest"
  b = subprocess.run(
    ["docker", "build", "-q", "-t", tag, "-"],
    input=df,
    capture_output=True,
    text=True,
  )
  if b.returncode != 0:
    pytest.skip(f"cannot build the no-gawk image: {b.stderr[-300:]}")
  ws = tmp_path / "ws"
  ws.mkdir()
  (ws / "run.cmk").write_text("__main__: flux.ok\n")
  shutil.copy(REPO / "compose.mk", ws / "compose.mk")
  for extra_env, label in ((), "hosted"), (("-e", "CMK_LANG=0"), "lean"):
    r = subprocess.run(
      [
        "docker",
        "run",
        "--rm",
        "-v",
        f"{ws}:{ws}",
        "-w",
        str(ws),
        "-e",
        "NO_COLOR=1",
        *extra_env,
        tag,
        "sh",
        "-c",
        "./compose.mk cmk run run.cmk",
      ],
      capture_output=True,
      text=True,
      timeout=300,
    )
    assert r.returncode == 0, f"{label}: {r.stderr[-500:]}"
