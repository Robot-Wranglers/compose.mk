"""Tests for demos/cmk/repl.cmk -- a bare REPL via REPL-as-execution-mode.

repl.cmk carries NO repl machinery: just a `# cmk_pragma ::: { "repl": true } :::` header + its own
targets (no tux.repl import, no host_only, no launcher).  `cmk run` sees the pragma and makes the
interactive harness the DEFAULT action; an explicit target bypasses the mode and runs (like
`python script.py` vs bare `python`).  The full TUI needs a tty + the (docker/go-built) wrapper and is
verified manually (a pty/pyte driver); here we cover the HEADLESS contract: the mode is selected and runs
in BATCH with no tty (stdin streams into the eval), and the dispatcher (tux.repl.kernel) runs targets on stdin.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_plugin, pytest.mark.covers_demo("repl.cmk")]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "repl.cmk"


def _dec(b):
  return (
    b.decode("utf-8", "replace")
    if isinstance(b, (bytes, bytearray))
    else (b or "")
  )


def _run(*args, **kw):
  if "input" not in kw:
    kw.setdefault("stdin", subprocess.DEVNULL)
  return subprocess.run(
    [str(DEMO), *args],
    cwd=str(REPO),
    capture_output=True,
    start_new_session=True,
    timeout=kw.pop("timeout", 90),
    **kw,
  )


def test_repl_mode_selected_and_batches_headless():
  # No args -> the `repl` pragma makes the harness the default action; no tty -> BATCH mode (empty stdin
  # -> a clean no-op).  Must announce the mode + the batch path, NOT build/launch the TUI.
  r = _run()
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "entering REPL execution mode" in out, out  # the pragma branch fired
  assert "streaming stdin into eval" in out, out  # batch, not the TUI
  for noise in ("go build", "docker run", "pty start"):
    assert noise not in out, out


def test_repl_batch_runs_piped_stdin():
  # No args + piped commands -> the pragma's batch mode streams them into the eval, as if typed.
  r = _run(input=b"demo.hello\n")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "hello from the repl demo" in out, out


def test_explicit_target_bypasses_repl_mode():
  # An explicit target runs it (bypassing the REPL default), like `python script.py`.
  r = _run("demo.hello")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "hello from the repl demo" in out, out
  assert "entering REPL execution mode" not in out, (
    out
  )  # NOT the mode -- the target ran


def test_repl_kernel_dispatches_from_stdin():
  # tux.repl.kernel is the generic core dispatcher the runtime wires for `repl: true`: each stdin line
  # is run through mk.kernel.each against the program.  Feed it a file-local target name.
  r = _run("tux.repl.kernel", input=b"demo.hello\n")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "hello from the repl demo" in out, out


def test_repl_kernel_lists_local_targets_at_launch():
  # At launch the kernel prints the program's LOCAL target namespace from CMK_REPL_TARGETS (the runtime
  # scrapes `name:`-at-line-start from the source).  Drive it headlessly with the env set + empty stdin.
  import os

  r = _run(
    "tux.repl.kernel",
    input=b"",
    env={**os.environ, "CMK_REPL_TARGETS": "demo.hello demo.wait __main__"},
  )
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "local targets" in out, out
  assert "demo.hello" in out and "demo.wait" in out, out
