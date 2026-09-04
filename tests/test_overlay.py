"""Tests for the __vm__ control-stack overlay demo (demos/overlay.mk).

`demos/overlay.mk demo.ui` opens a 2-pane host-tmux layout (main __vm__ run + a live gum panel
reflecting the CEK control stack).  That path needs a tty + tmux, so it can only be exercised
under a real/pseudo terminal; here we cover the HEADLESS contract:

  * `coro.demo` (the program pane runs) completes when run inline, and
  * `demo.ui` DEGRADES cleanly with no tty (the `[ -t 1 ]` guard execs `coro.demo` instead of
    trying to attach tmux) -- so CI never blocks and never emits a tmux error.

Both are run with start_new_session=True (setsid) + stdin=DEVNULL + a timeout, so the suite
can never block on a tmux attach even if the guard regressed.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module]

REPO = Path(__file__).resolve().parent.parent
OVERLAY_DEMO = REPO / "demos" / "overlay.mk"


def _run_headless(*args):
  return subprocess.run(
    [str(OVERLAY_DEMO), *args],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    start_new_session=True,  # detach the controlling terminal -> demo.ui takes the no-tty path
    timeout=60,
  )


def test_overlay_coro_runs_headless():
  # The program pane's target: the __vm__ coroutine runs to completion inline (no tmux).
  r = _run_headless("coro.demo")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "Waiting for 1 seconds" in out, out  # io.wait/1 per phase ran
  assert "coro: resume (phase 2) -> done" in out, out  # coroutine completed


def test_overlay_demo_ui_degrades_headless():
  # demo.ui with no tty -> the guard execs coro.demo instead of attaching tmux: sane output +
  # exit code, and crucially NO tmux error (it must not even try to start a server/attach).
  r = _run_headless("demo.ui")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "coro: resume (phase 2) -> done" in out, (
    out
  )  # degraded to the coroutine
  for tmux_err in (
    "no server running",
    "open terminal failed",
    "not a terminal",
  ):
    assert tmux_err not in out, out
