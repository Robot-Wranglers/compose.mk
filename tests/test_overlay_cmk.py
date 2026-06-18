"""Tests for the __vm__ overlay demo (demos/cmk/overlay.cmk), now built on cmk.tux.repl.

`overlay.cmk demo.ui` is `cmk.tux.repl(read=overlay.read eval=overlay.eval print=overlay.print)` --
the reusable 3-region Bubbletea REPL imported from .cmk/tux.repl.cmk: a scrolling stream
(print), a multiline input area (color-coded IPython In[N]/Out[N] preambles), and a one-line
mode-line (read).  The full TUI needs a tty + the (docker-built) wrapper binary, so it is verified
manually; here we cover the HEADLESS contract:

  * coro.demo (the reflective coroutine) completes when run inline (an explicit target bypasses the mode);
  * a bare run (the `repl` object pragma's default action) DEGRADES with no tty (the macro's
    ${io.tty.stdin} gate logs + exits, no build/exec);
  * overlay.read (the mode-line source) emits a K/E summary line;
  * overlay.eval (the input sink) dispatches a target name read from stdin.

Output is captured as BYTES and decoded with errors="replace" -- the cmk machinery emits multibyte
glyphs that can be split across a streamed/partial read (e.g. on the read target's timeout).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "overlay.cmk"


def _dec(b):
  return b.decode("utf-8", "replace") if isinstance(b, (bytes, bytearray)) else (b or "")


def _run_headless(*args, **kw):
  if "input" in kw and isinstance(kw["input"], str):
    kw["input"] = kw["input"].encode()
  if "input" not in kw:
    kw.setdefault("stdin", subprocess.DEVNULL)
  return subprocess.run(
    [str(DEMO), *args],
    cwd=str(REPO),
    capture_output=True,  # bytes (no text=); decode via _dec
    start_new_session=True,  # detach controlling terminal -> demo.ui takes the no-tty path
    timeout=kw.pop("timeout", 60),
    **kw,
  )


def test_overlay_cmk_coro_runs_headless():
  r = _run_headless("coro.demo")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "Waiting for 1 seconds" in out, out  # io.wait/1 per phase
  assert "done phase=2" in out, out  # cmk.log.target of the final phase


def test_overlay_cmk_mode_degrades_headless():
  # No args -> the `repl` object pragma makes the 3-region harness the default action; no tty -> the
  # macro's gate logs + exits.  Must announce the mode (with the wired regions), then degrade -- NOT
  # build (docker) or launch the TUI.
  r = _run_headless()
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "entering REPL execution mode" in out, out  # the pragma branch fired
  assert "read=overlay.read" in out and "print=overlay.print" in out, out  # object schema -> regions
  assert "no tty so skipping tux.repl" in out, out  # degraded with a message, not the TUI
  for noise in ("go build", "docker run", "pty start"):
    assert noise not in out, out


def test_overlay_read_emits_a_summary_line():
  # overlay.read is the mode-line source: a long-lived loop emitting K/E summary lines.  It never
  # exits, so let it time out and inspect the partial output.
  try:
    r = _run_headless("overlay.read", timeout=6)
    out = _dec(r.stdout) + _dec(r.stderr)  # not reached (infinite loop)
  except subprocess.TimeoutExpired as e:
    out = _dec(e.stdout) + _dec(e.stderr)
  assert "__vm__ |> K=" in out, out


def test_overlay_eval_dispatches_a_target_from_stdin():
  # overlay.eval is the input sink: each line (a target name) is dispatched as a fresh run.  Feed it
  # "coro.demo" on stdin and confirm the coroutine ran (output streams back, the REPL's "PRINT").
  r = _run_headless("overlay.eval", input="coro.demo\n")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "done phase=2" in out, out
