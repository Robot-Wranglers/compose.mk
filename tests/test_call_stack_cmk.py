"""Smoke tests for demos/cmk/call_stack.cmk -- the cmk-callform twin of demos/call_stack.mk.

Behavior is identical to the .mk (fully covered by test_call_stack.py); these two cases just
confirm the `cmk.__vm__.X(..)` callforms LOWER and run correctly at runtime (the distinct path),
including that a transfer's continuation (the trailing `C`) still resumes.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "call_stack.cmk"


def _stack(*goals):
  r = subprocess.run(
    [str(DEMO), *goals],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=60,
  )
  out = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout)
  return r.returncode, [ln for ln in out.splitlines() if ln.strip()]


def test_goto_back_loop():
  # `cmk.__vm__.goto(count/..)` -- a bounded loop over the control stack.
  rc, out = _stack("count/3")
  assert rc == 0, out
  assert out == ["count 3", "count 2", "count 1", "count 0", "  done"]


def test_call_return_resumes_continuation():
  # `cmk.__vm__.call(probe/..)` + `cmk.__vm__.return()`; the saved continuation [C] resumes.
  rc, out = _stack("find/hit", "C")
  assert rc == 0, out
  assert out == ["find hit -> call probe/hit", "  probe hit (early return)", "C"]
