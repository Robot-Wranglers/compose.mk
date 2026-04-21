"""Tests for the MAKE_CLI control-stack interface (the `__vm__` module).

The goals after the current target on the command line are the continuation, exposed as
a control stack: inspect (peek/rest/depth), grow (push), shrink (drop), and jump (goto,
call/return). `__vm__` extends the generic, MAKE_CLI-free `control_stack` module. Jumps
transfer via mk.yield, so they need a supervisor; these drive the interface through
demos/call_stack.mk run via its `mk.interpret` shebang's runtime:

    ./compose.mk mk.interpret demos/call_stack.mk <goals>

Each test asserts the exact stdout (the demo's echo/printf lines); make chatter and the
compiler/yield logs go to stderr.
"""

import re
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent


def _stack(cmk, *goals):
  # Drive the demo through its shebang's runtime: `mk.interpret` gives the supervisor
  # that jumps need (BASE_ENV sets CMK_SUPERVISOR=0, so force it on), and
  # CMK_DISABLE_HOOKS=1 keeps the flux.pre/post hook tokens OUT of MAKE_CLI so the
  # continuation the cstack reads stays clean -- both encoded in the demo's shebang.
  # cwd=repo so the relative demos/call_stack.mk resolves.
  r = cmk(
    "mk.interpret",
    "demos/call_stack.mk",
    *goals,
    env={"CMK_SUPERVISOR": "1", "CMK_DISABLE_HOOKS": "1"},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  out = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout)
  return [ln for ln in out.splitlines() if ln.strip()]


def test_inspect_peek_rest_depth(cmk):
  # the pending goals after `peek` ARE the control stack.
  assert _stack(cmk, "peek", "A", "B") == ["top=A rest=[B] depth=2", "A", "B"]


def test_push_implicit_return(cmk):
  # push runs the subroutine, THEN resumes the caller's continuation.
  assert _stack(cmk, "need.setup", "C") == [
    "need.setup -> push setup",
    "  setup",
    "C",
  ]


def test_drop_skips_next(cmk):
  # drop (pop) skips the next pending goal: A is skipped, B runs.
  out = _stack(cmk, "skipper", "A", "B")
  assert out == ["skipper -> drop next", "B"]
  assert "A" not in out


def test_goto_skips_intervening(cmk):
  # goto arrive: B is skipped; arrive then the rest (C) run.
  out = _stack(cmk, "router", "B", "arrive", "C")
  assert out == ["router -> goto arrive", "  arrive", "C"]
  assert "B" not in out


def test_goto_back_loop(cmk):
  # a bounded loop expressed purely as goto-back over the control stack.
  assert _stack(cmk, "count/3") == [
    "count 3",
    "count 2",
    "count 1",
    "count 0",
    "  done",
  ]


def test_call_return_early(cmk):
  # call saves [C]; the callee returns early; return resumes the saved continuation.
  assert _stack(cmk, "find/hit", "C") == [
    "find hit -> call probe/hit",
    "  probe hit (early return)",
    "C",
  ]


def test_call_return_fallthrough(cmk):
  # the callee always returns, so the miss path also resumes [C].
  assert _stack(cmk, "find/miss", "C") == [
    "find miss -> call probe/miss",
    "  probe miss",
    "C",
  ]
