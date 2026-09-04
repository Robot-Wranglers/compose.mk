"""Tests for the __vm__ overlay demo (demos/cmk/overlay.cmk), now built on cmk.tux.repl.

`overlay.cmk` (bare, via its `repl` object pragma) launches `cmk.tux.repl(eval=overlay.eval
print=overlay.print exit_after=1)` -- the reusable 3-region Bubbletea REPL imported from
.cmk/tux.repl.cmk: a scrolling stream (print), a multiline input area (color-coded IPython
In[N]/Out[N] preambles), and a one-line mode-line (read).  This demo does NOT wire `read`: the
mode-line inherits the runtime default, the core `tux.repl.modeline` (always-on diagnostics + the
__vm__ stack summary -- the successor that folds in the old demo-local `overlay.read`).  The full TUI
needs a tty + the (docker-built) wrapper binary, so it is verified manually; here we cover the
HEADLESS contract:

  * coroutines.demo (imported from the vm-coroutines.cmk demo) completes when run inline (an explicit target bypasses the mode);
  * a bare run (the `repl` object pragma's default action) DEGRADES with no tty (the macro's
    ${io.tty.stdin} gate logs + exits, no build/exec);
  * tux.repl.modeline (the DEFAULT mode-line source) emits a JSON summary line;
  * overlay.eval (the input sink) dispatches a target name read from stdin.

Output is captured as BYTES and decoded with errors="replace" -- the cmk machinery emits multibyte
glyphs that can be split across a streamed/partial read (e.g. on the read target's timeout).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module, pytest.mark.covers_demo("overlay.cmk")]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "overlay.cmk"


def _dec(b):
  return (
    b.decode("utf-8", "replace")
    if isinstance(b, (bytes, bytearray))
    else (b or "")
  )


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
  r = _run_headless(
    "coroutines.demo"
  )  # imported from the vm-coroutines.cmk demo (prefix=demos/cmk)
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "Waiting for 1 seconds" in out, (
    out
  )  # coroutines.wait:=1 -> io.wait/1 per phase
  assert "done phase=2" in out, out  # cmk.log of the final phase


def test_overlay_cmk_mode_degrades_headless():
  # No args -> the `repl` object pragma makes the 3-region harness the default action; no tty -> the
  # macro's gate logs + exits.  Must announce the mode (with the wired regions), then degrade -- NOT
  # build (docker) or launch the TUI.
  r = _run_headless()
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "entering REPL execution mode" in out, out  # the pragma branch fired
  # object schema -> regions; `read` is NOT in the kwargs (it defaults to the core tux.repl.modeline)
  assert "print=overlay.print" in out and "eval=overlay.eval" in out, out
  assert "read=overlay.read" not in out, (
    out
  )  # the demo no longer wires its own read
  assert "streaming stdin into eval" in out, (
    out
  )  # headless BATCH (empty stdin -> no-op)
  for noise in ("go build", "docker run", "pty start"):
    assert noise not in out, out


def test_overlay_modeline_emits_summary_json():
  # The mode-line source DEFAULTS to the core tux.repl.modeline (successor to overlay.read): a long-lived
  # loop emitting one `mode_segs` metadata object per line -- the feeder owns the FORMATTING (the diag
  # fingerprint + per-segment style/priority), the Go wrapper only elides to width.  It never exits, so let
  # it time out and inspect the partial output.  No coro.demo running -> no __vm__ frames, but the always-on
  # diagnostics segment is present.  (The "^D quit" hint is wrapper-owned, NOT feeder-emitted, so it is not
  # in this raw feeder output.)
  try:
    r = _run_headless("tux.repl.modeline", timeout=6)
    out = _dec(r.stdout) + _dec(r.stderr)  # not reached (infinite loop)
  except subprocess.TimeoutExpired as e:
    out = _dec(e.stdout) + _dec(e.stderr)
  assert '"mode_segs"' in out and '"s":"dim"' in out, out


def test_overlay_eval_dispatches_a_target_from_stdin():
  # overlay.eval is the input sink: each line (a target name) is dispatched as a fresh run.  Feed it
  # "coroutines.demo" on stdin and confirm the coroutine ran (output streams back, the REPL's "PRINT").
  r = _run_headless("overlay.eval", input="coroutines.demo\n")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "done phase=2" in out, out
