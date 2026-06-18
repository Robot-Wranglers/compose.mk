"""Tests for the trampoline + tree control-stack (the migrated `__vm__` module).

`__vm__` is a CEK machine over the make goal-list: C = current goal, E = environment
(bindings), K = the control-stack tree of saved {cont,env} frames. Control transfers
re-dispatch FLAT through the supervisor's trampoline loop (no process nesting); call/
return/yield manage K frames carrying E. These drive demos/vm.mk via its `mk.interpret`
shebang runtime (the supervisor that the trampoline needs):

    ./compose.mk mk.interpret demos/vm.mk <goals>

Each test asserts exact stdout (the demo's echo lines); compiler/yield/make chatter and
the fork branch's backtrace go to stderr.
"""

import re
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent


def _vm(cmk, *goals):
  # Drive demos/vm.mk through the interpreter (CMK_SUPERVISOR=1 for the trampoline loop;
  # CMK_DISABLE_HOOKS=1 keeps flux.pre/post tokens out of the continuation). cwd=repo so
  # the relative demos/vm.mk resolves.
  r = cmk(
    "mk.interpret",
    "demos/vm.mk",
    *goals,
    env={"CMK_SUPERVISOR": "1", "CMK_DISABLE_HOOKS": "1"},
    cwd=str(REPO),
  )
  assert r.ok, r.stderr
  out = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout)
  return [ln for ln in out.splitlines() if ln.strip()]


def test_flat_trampoline_loop(cmk):
  # A goto-loop runs to completion AND flat: every hop reports the SAME MAKELEVEL, which
  # proves the trampoline does not nest make processes (the old eval-nest model would
  # increment it every hop).
  out = _vm(cmk, "count/6")
  labels = [ln.split(" (")[0] for ln in out if ln.startswith("count ")]
  assert labels == ["count 6", "count 5", "count 4", "count 3", "count 2", "count 1", "count 0"]
  assert out[-1] == "done"
  levels = {re.search(r"MAKELEVEL=(\d+)", ln).group(1) for ln in out if "MAKELEVEL=" in ln}
  assert len(levels) == 1, f"expected a constant MAKELEVEL (flat), got {levels}"


def test_call_return_resumes_continuation(cmk):
  # call saves the caller's continuation as a K frame and jumps; return resumes it.
  assert _vm(cmk, "call.demo", "after") == [
    "call.demo -> call greet",
    "  greet -> return",
    "after (resumed continuation)",
  ]


def test_backtrace_tree(cmk):
  # Two nested calls; the backtrace reconstructs the K tree (outermost first) + live cont.
  assert _vm(cmk, "bt.demo") == [
    "at level2; full control tree:",
    "== vm backtrace ==",
    "  [0] call level1",
    "  [1] call level2",
    "  ...live: []",
  ]


def test_coroutine_reentrancy_via_env(cmk):
  # The resume point is a binding `phase` in the environment E (getenv/setenv); re-entering
  # the same target dispatches on it -- the case arms act as resume labels.
  assert _vm(cmk, "coro.demo") == [
    "coro: enter (phase 0) -> init",
    "coro: resume (phase 1) -> step",
    "coro: resume (phase 2) -> done",
  ]


def test_mutual_recursion_shared_env(cmk):
  # ping/pong yield to each other, sharing the env binding `turns` threaded across gotos.
  assert _vm(cmk, "pingpong") == [
    "ping (4) -> yield to pong",
    "pong (3) -> yield to ping",
    "ping (2) -> yield to pong",
    "pong (1) -> yield to ping",
    "ping: out of turns",
  ]


def test_generator_yield_value_into_caller_env(cmk):
  # __vm__.yield writes a value into the CALLER's env; the resumed caller reads it back.
  assert _vm(cmk, "gen.demo", "consume") == [
    "gen.demo -> call producer",
    "  producer -> yield 42 into caller's env",
    "consume: caller received yielded=42",
  ]
