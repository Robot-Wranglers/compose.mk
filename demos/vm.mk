#!/usr/bin/env -S CMK_DISABLE_HOOKS=1 ./compose.mk mk.interpret
# vm.mk: exercises the trampoline + tree control-stack (core `__vm__`).
#
#   `__vm__` is the make-VM's control interface (an instance of the generic
#   `control_stack`).  The goal-list is the program; transfers re-dispatch FLAT through
#   the supervisor's trampoline loop (no process nesting); call/return/fork frames live
#   on a run-shared tree, and each frame carries its environment E (the VM is a CEK
#   machine: C=current goal, E=environment, K=control-stack tree).  Run via the shebang
#   (the supervisor is required):
#
#     ./demos/vm.mk loop.demo         # flat goto-loop: MAKELEVEL stays constant (no nesting)
#     ./demos/vm.mk bt.demo           # backtrace of a 2-deep call tree
#     ./demos/vm.mk call.demo after   # call/return resuming the saved continuation
#     ./demos/vm.mk fork.demo         # a flux.pipeline fork reflected as tree branches
#     ./demos/vm.mk coro.demo         # re-entrant coroutine (env binding + case = resume)
#     ./demos/vm.mk pingpong          # mutual recursion: two coroutines share an env binding
#     ./demos/vm.mk gen.demo consume  # generator: producer yields a VALUE into caller's env
include compose.mk
# The __vm__ plugin (control stack + CEK machine) is no longer in core -- import it.
$(call include.plugins, virtual-machine.cmk)

__main__: loop.demo

# ── FLAT EXECUTION (trampoline) ─────────────────────────────────────────────
# A bounded loop expressed as goto-back.  Under the OLD eval-nesting model each hop would
# add a make process; under the trampoline every hop runs at top level, so MAKELEVEL stays
# CONSTANT regardless of the count (the proof of flatness).
loop.demo:; @${make} count/8
count/%:
	@printf 'count %s (MAKELEVEL=%s)\n' "${*}" "$${MAKELEVEL}"
	@[ "${*}" = 0 ] && echo done || $(call __vm__.goto, count/$$(( ${*} - 1 )))

# ── CALL / RETURN (tree frames) ─────────────────────────────────────────────
# call saves the caller's continuation as a frame and jumps; return resumes it.
# `./demos/vm.mk call.demo after` -> greet runs, then `after` (the saved continuation).
call.demo:
	@echo "call.demo -> call greet"
	@$(call __vm__.call, greet)
greet:
	@echo "  greet -> return"
	@$(call __vm__.return)
after:; @echo "after (resumed continuation)"

# ── BACKTRACE FROM DEPTH ────────────────────────────────────────────────────
# Two nested calls, then dump the control tree from the leaf.
bt.demo:;   @$(call __vm__.call, level1)
level1:;    @$(call __vm__.call, level2)
level2:
	@echo "at level2; full control tree:"
	@${make} __vm__.backtrace

# ── FORK (tree branches; execution via flux.pipeline) ───────────────────────
# fork records a branching frame, then runs the branches via core flux.pipeline.  A
# backtrace inside a branch shows the fork frame WITH its sibling branches.
fork.demo:; @$(call __vm__.fork, brancha branchb)
brancha:; @echo "branch a:" && ${make} __vm__.backtrace 1>&2
branchb:; @${stream.stdin} >/dev/null 2>&1 ; echo "branch b"

# ── COROUTINE / RE-ENTRANCY (CEK environment + case = resume labels) ─────────
# The resume point is a binding `phase` in the environment E, read/written via the
# explicit interface (__vm__.getenv / __vm__.setenv).  Re-entering the SAME target and
# dispatching on E.phase makes the case arms behave as resume labels.  Control keeps
# re-entering `coro`; the state lives in E, not the goal.
coro.demo:; @$(call __vm__.setenv, phase, 0) && $(call __vm__.goto, coro)
coro:
	@case "`$(call __vm__.getenv, phase)`" in \
		0) echo "coro: enter (phase 0) -> init"  && $(call __vm__.setenv, phase, 1) && $(call __vm__.goto, coro) ;; \
		1) echo "coro: resume (phase 1) -> step" && $(call __vm__.setenv, phase, 2) && $(call __vm__.goto, coro) ;; \
		2) echo "coro: resume (phase 2) -> done" ;; \
	esac

# ── MUTUAL RECURSION (two coroutines sharing a binding in the threaded env) ──
# ping and pong yield to each other (flat gotos); `turns` is a binding in the current
# environment E, threaded across the gotos (not a global) until it runs out.
pingpong:; @$(call __vm__.setenv, turns, 4) && $(call __vm__.goto, ping)
ping:
	@n="`$(call __vm__.getenv, turns)`" ; [ "$$n" = 0 ] \
		&& echo "ping: out of turns" \
		|| { echo "ping ($$n) -> yield to pong" && $(call __vm__.setenv, turns, $$(( n - 1 ))) && $(call __vm__.goto, pong) ; }
pong:
	@n="`$(call __vm__.getenv, turns)`" ; [ "$$n" = 0 ] \
		&& echo "pong: out of turns" \
		|| { echo "pong ($$n) -> yield to ping" && $(call __vm__.setenv, turns, $$(( n - 1 ))) && $(call __vm__.goto, ping) ; }

# ── GENERATOR: yield a VALUE into the caller's environment ───────────────────
# __vm__.yield (distinct from process-level mk.yield) writes a value into the CALLER's
# frame environment, then returns control.  The caller reads it from its own (now-current)
# environment after the call returns.  Run: ./demos/vm.mk gen.demo consume
gen.demo:; @echo "gen.demo -> call producer" && $(call __vm__.call, producer)
producer:
	@echo "  producer -> yield 42 into caller's env" && $(call __vm__.yield, 42)
consume:
	@printf 'consume: caller received yielded=%s\n' "`$(call __vm__.getenv, yielded)`"
