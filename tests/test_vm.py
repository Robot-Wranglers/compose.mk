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

pytestmark = [pytest.mark.unit, pytest.mark.external_module]

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
  assert labels == [
    "count 6",
    "count 5",
    "count 4",
    "count 3",
    "count 2",
    "count 1",
    "count 0",
  ]
  assert out[-1] == "done"
  levels = {
    re.search(r"MAKELEVEL=(\d+)", ln).group(1)
    for ln in out
    if "MAKELEVEL=" in ln
  }
  assert len(levels) == 1, (
    f"expected a constant MAKELEVEL (flat), got {levels}"
  )


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
  # vm.yield writes a value into the CALLER's env; the resumed caller reads it back.
  assert _vm(cmk, "gen.demo", "consume") == [
    "gen.demo -> call producer",
    "  producer -> yield 42 into caller's env",
    "consume: caller received yielded=42",
  ]


def test_self_model_long_format_accessors(cmk):
  # The long-format reflective accessors project the live CEK self-model: `__vm__` (the whole
  # snapshot), `__vm__.kontinuation` (K), `__vm__.instruction_pointer` (C).  self.demo calls
  # self.report (so K is non-empty), then prints each -- read INLINE in the running machine.
  out = _vm(cmk, "self.demo")
  text = "\n".join(out)
  assert "self.demo -> call self.report" in out, text
  sm = next((ln for ln in out if ln.startswith("self-model")), "")
  assert '"ip"' in sm and '"k"' in sm and '"chain"' in sm, (
    sm
  )  # __vm__ IS the snapshot (CEK fields, compact JSON on one line)
  # kontinuation (K) = the saved frames; pretty-printed JSON, so check the whole output.
  assert "kontinuation(K):" in text, text
  assert '"goal": "self.report"' in text, text  # the K frame for self.report
  ip = next((ln for ln in out if ln.startswith("instr-pointer")), "")
  assert "self.report" in ip, ip  # C = the innermost goal (single value)


def test_scheduler_registers_reflect_the_running_machine(cmk):
  # The seven scheduler registers are exported on each dispatch hop as a read-only reflection
  # surface. self.report prints C/step/codes from the registers ($(__ip__) etc.) beside the
  # snapshot-derived accessors: the register C must agree with the snapshot's instruction pointer
  # (one self-model, two layers), the step is a positive int within budget, and the raw POSIX wait
  # status (posix) is surfaced separately from the resolved exit code.
  out = _vm(cmk, "self.demo")
  text = "\n".join(out)
  reg = next((ln for ln in out if ln.startswith("register C/step")), "")
  ip = next((ln for ln in out if ln.startswith("instr-pointer")), "")
  assert "self.report" in reg and "self.report" in ip, text  # register C == snapshot C
  m = re.search(r"step (\d+)/(\d+)", reg)
  assert m and int(m.group(1)) >= 1 and int(m.group(2)) >= int(m.group(1)), reg
  codes = next((ln for ln in out if ln.startswith("register codes")), "")
  assert re.search(r"posix=\d", codes) and "exit=" in codes, codes  # raw vs resolved, both surfaced


def test_vm_transfer_never_triggers_root_fault(cmk):
  # A VM goto/continuation is a ROUTE, not a fault: the trampoline classifies the mbox transfer
  # BEFORE the root handler moves, so re-diagnosing an interpreted-program continuation can never
  # leak a spurious `No rule to make target 'count/...'` (nor a `RuleMissing:` header).  Pins the
  # router-before-error-handling ordering for the VM path specifically.
  r = cmk(
    "mk.interpret", "demos/vm.mk", "count/3",
    env={"CMK_SUPERVISOR": "1", "CMK_DISABLE_HOOKS": "1"}, cwd=str(REPO),
  )
  text = re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)
  assert "count 0" in text, text                        # the loop ran to completion
  assert "No rule to make target 'count/" not in text, text
  assert "RuleMissing:" not in text, text
