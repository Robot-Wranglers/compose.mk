"""Tests for demos/repl.mk -- the canonical way to add a REPL to a PLAIN Makefile, WITHOUT cmk-pragma.

repl.mk is a vanilla `include compose.mk` Makefile (a `make -f` shebang) that imports the tux.repl
plugin and wires `__main__: tux.repl/t1,t2,t3`.  The `tux.repl/%` plugin helper launches the same
Bubbletea harness the `.cmk` paths use, but over the LIVE makefile (the makefile itself is the runner --
nothing is compiled).  The full TUI needs a tty + the (docker/go-built) wrapper and is verified manually
(a pty/pyte driver confirms the launch banner lists t1/t2/t3 and typing one dispatches it); here we cover
the HEADLESS contract: it degrades with no tty, and a target runs directly (bypassing the REPL).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "repl.mk"


def _dec(b):
  return b.decode("utf-8", "replace") if isinstance(b, (bytes, bytearray)) else (b or "")


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


def test_repl_mk_degrades_headless():
  # No tty -> the macro's gate logs + exits; must NOT build (docker/go) or launch the TUI.
  r = _run()
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "no tty so skipping tux.repl" in out, out
  for noise in ("go build", "docker run", "pty start"):
    assert noise not in out, out


def test_repl_mk_explicit_target_bypasses_repl():
  # A target runs directly (the REPL is only the __main__ default action).
  r = _run("t1")
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "t1: hello from the plain-makefile repl" in out, out
  assert "no tty so skipping tux.repl" not in out, out  # the REPL was NOT the action
