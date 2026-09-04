#!/usr/bin/env -S CMK_DISABLE_HOOKS=1 ./compose.mk mk.interpret
#
# call_stack.mk: the MAKE_CLI continuation, used as a control stack.
#   The goals AFTER the current target on the command line are the
#   continuation -- "what's left to do".  compose.mk exposes that via the
#   `__vm__` module (the make process as a virtual machine whose program is
#   the goal list): inspect it (peek/rest/depth), grow it (push), shrink it
#   (drop), or jump around it (goto, and call/return with frames).
#   `mk.yield` is the transfer primitive.  `__vm__` extends the generic,
#   MAKE_CLI-free `control_stack` module; both ship in compose.mk.
#
# Jumps need a supervisor (see shebang -- compose.mk runs this via
# `mk.interpret`, NOT plain `make -f`), so run the demo through its
# shebang:
#
#   ./demos/call_stack.mk peek A B
#   ./demos/call_stack.mk need.setup C
#   ./demos/call_stack.mk router B arrive C
#   ./demos/call_stack.mk count/3
#   ./demos/call_stack.mk find/hit C

include compose.mk
# The __vm__ plugin (control stack + CEK machine) lives outside core --
# import it.
$(call include.plugins, virtual-machine.cmk)

# The no-args default: showcase the bounded goto-loop.
__main__: count/3

A:; @echo A
B:; @echo B
C:; @echo C

peek:
	@# Inspect: the pending goals after this target are the control stack.
	@printf 'top=%s rest=[%s] depth=%s\n' \
		"`${__vm__.peek}`" "`${__vm__.rest}`" "`${__vm__.depth}`"

need.setup:
	@# Push: subroutine call with implicit return to the caller's continuation.
	@echo "need.setup -> push setup"
	$(call vm.push, setup)
setup:; @echo "  setup"

skipper:
	@# Drop: pop/skip the next pending goal.
	@echo "skipper -> drop next"
	$(call vm.drop)

router:
	@# Goto: tail-jump forward -- skip goals before the target, keep goals after
	@# it.
	@echo "router -> goto arrive"
	$(call vm.goto, arrive)
arrive:; @echo "  arrive"

count/%:
	@# Loop: a bounded loop expressed purely as goto-back over the control
	@# stack.
	@echo "count ${*}"
	@[ "${*}" = 0 ] && echo "  done" || $(call vm.goto, count/$$((${*}-1)))

find/%:
	@# Call / return: disciplined non-local return (the callee always returns).
	@echo "find ${*} -> call probe/${*}"
	$(call vm.call, probe/${*})
probe/%:
	@case "${*}" in hit) echo "  probe hit (early return)";; *) echo "  probe miss";; esac \
	; $(call vm.return)
