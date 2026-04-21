#!/usr/bin/env -S CMK_DISABLE_HOOKS=1 ./compose.mk mk.interpret
#
# vm.mk: exercises the trampoline + tree control-stack (core `__vm__`).
#
#   `__vm__` is the make-VM's control interface (an instance of the generic
#   `control_stack`).  The goal-list is the program; transfers re-dispatch
#   flat through the supervisor's trampoline loop (no process nesting);
#   call/return/fork frames live on a run-shared tree, and each frame
#   carries its environment E (the VM is a CEK machine: C=current goal,
#   E=environment, K=control-stack tree).  Run via the shebang (the
#   supervisor is required):
#
#     ./demos/vm.mk loop.demo
#         flat goto-loop: MAKELEVEL stays constant (no nesting)
#     ./demos/vm.mk bt.demo
#         backtrace of a 2-deep call tree
#     ./demos/vm.mk call.demo after
#         call/return resuming the saved continuation
#     ./demos/vm.mk fork.demo
#         a flux.pipeline fork reflected as tree branches
#     ./demos/vm.mk coro.demo
#         re-entrant coroutine (env binding + case = resume)
#     ./demos/vm.mk pingpong
#         mutual recursion: two coroutines share an env binding
#     ./demos/vm.mk gen.demo consume
#         generator: producer yields a value into caller's env
#     ./demos/vm.mk self.demo
#         inspect the live self-model (long-format accessors + scheduler registers)
include compose.mk
# The __vm__ plugin (control stack + CEK machine) lives outside core --
# import it.
$(call include.plugins, virtual-machine.cmk)

__main__: loop.demo

# ── flat execution (trampoline)
# ───────────────────────────────────────────── A bounded loop expressed as
# goto-back.  Every hop runs at top level through the trampoline, so
# MAKELEVEL stays constant regardless of the count (the proof of flatness).
loop.demo:; @${make} count/8
count/%:
	@printf 'count %s (MAKELEVEL=%s)\n' "${*}" "$${MAKELEVEL}"
	@[ "${*}" = 0 ] && echo done || $(call vm.goto, count/$$(( ${*} - 1 )))

# ── call / return (tree frames)
# ───────────────────────────────────────────── call saves the caller's
# continuation as a frame and jumps; return resumes it.  `./demos/vm.mk
# call.demo after` -> greet runs, then `after` (the saved continuation).
call.demo:
	@echo "call.demo -> call greet"
	@$(call vm.call, greet)
greet:
	@echo "  greet -> return"
	@$(call vm.return)
after:; @echo "after (resumed continuation)"

# ── backtrace from depth
# ──────────────────────────────────────────────────── Two nested calls,
# then dump the control tree from the leaf.
bt.demo:;   @$(call vm.call, level1)
level1:;    @$(call vm.call, level2)
level2:
	@echo "at level2; full control tree:"
	@${make} __vm__.backtrace

# ── fork (tree branches; execution via flux.pipeline)
# ─────────────────────── fork records a branching frame, then runs the
# branches via core flux.pipeline.  A backtrace inside a branch shows the
# fork frame with its sibling branches.
fork.demo:; @$(call vm.fork, brancha branchb)
brancha:; @echo "branch a:" && ${make} __vm__.backtrace 1>&2
branchb:; @${stream.stdin} >/dev/null 2>&1 ; echo "branch b"

# ── coroutine / re-entrancy (CEK environment + case = resume labels)
# ───────── The resume point is a binding `phase` in the environment E,
# read/written via the explicit interface (__vm__.getenv / __vm__.setenv).
# Re-entering the same target and dispatching on E.phase makes the case
# arms behave as resume labels.  Control keeps re-entering `coro`; the
# state lives in E, not the goal.
coro.demo:; @$(call __vm__.setenv, phase, 0) && $(call vm.goto, coro)
coro:
	@case "`$(call __vm__.getenv, phase)`" in \
		0) echo "coro: enter (phase 0) -> init"  && $(call __vm__.setenv, phase, 1) && $(call vm.goto, coro) ;; \
		1) echo "coro: resume (phase 1) -> step" && $(call __vm__.setenv, phase, 2) && $(call vm.goto, coro) ;; \
		2) echo "coro: resume (phase 2) -> done" ;; \
	esac

# ── mutual recursion (two coroutines sharing a binding in the threaded
# env) ── ping and pong yield to each other (flat gotos); `turns` is a
# binding in the current environment E, threaded across the gotos (not a
# global) until it runs out.
pingpong:; @$(call __vm__.setenv, turns, 4) && $(call vm.goto, ping)
ping:
	@n="`$(call __vm__.getenv, turns)`" ; [ "$$n" = 0 ] \
		&& echo "ping: out of turns" \
		|| { echo "ping ($$n) -> yield to pong" && $(call __vm__.setenv, turns, $$(( n - 1 ))) && $(call vm.goto, pong) ; }
pong:
	@n="`$(call __vm__.getenv, turns)`" ; [ "$$n" = 0 ] \
		&& echo "pong: out of turns" \
		|| { echo "pong ($$n) -> yield to ping" && $(call __vm__.setenv, turns, $$(( n - 1 ))) && $(call vm.goto, ping) ; }

# ── generator: yield a value into the caller's environment
# ─────────────────── vm.yield (distinct from process-level mk.yield)
# writes a value into the caller's frame environment, then returns control.
# The caller reads it from its own (now-current) environment after the call
# returns.  Run: ./demos/vm.mk gen.demo consume
gen.demo:; @echo "gen.demo -> call producer" && $(call vm.call, producer)
producer:
	@echo "  producer -> yield 42 into caller's env" && $(call vm.yield, 42)
consume:
	@printf 'consume: caller received yielded=%s\n' "`$(call __vm__.getenv, yielded)`"

# ── self-model: the long-format reflective accessors
# ───────────────────────── Inspect the live machine via the descriptive
# long-format names: the whole self-model (`__vm__`), its kontinuation K
# (`__vm__.kontinuation`), and its instruction pointer C
# (`__vm__.instruction_pointer`).  `self.demo` calls `self.report` so K is
# non-empty.  These are read inline (same process), so the MAKE_SUPER-keyed
# K stack is the live one; an external observer would instead read the
# glob-based `${__vm__}` snapshot.  `self.report` also prints the same cells
# from the scheduler registers (`$(__ip__)`/`$(__step__)`/...) -- the cheap
# always-on layer the snapshot reads from, a make-var read vs the structured view.
self.demo:; @echo "self.demo -> call self.report" && $(call vm.call, self.report)
self.report:
	@printf 'self-model     : %s\n' "$$( ${__vm__} )"
	@printf 'kontinuation(K): %s\n' "$$( ${__vm__.kontinuation} )"
	@printf 'instr-pointer C: %s\n' "$$( ${__vm__.instruction_pointer} )"
	@# the same cells from the cheap always-on scheduler registers (a make-var read,
	@# vs the shell-captured snapshot above -- both project the one CEK self-model).
	@printf 'register C/step : %s  (step %s/%s)\n' "$(__ip__)" "$(__step__)" "$(__step_budget__)"
	@printf 'register codes  : posix=%s exit=%s\n' "$(__posix_code__)" "$(__exit_code__)"
	@$(call vm.return)
