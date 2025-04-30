#!/usr/bin/env -S CMK_DISABLE_HOOKS=1 ./compose.mk mk.interpret
# demos/interpreter-2.mk: 
#   Demonstrating compose.mk as an alternate interpreter for make.
#   This is mostly used for inheriting signals/supervisors.  
#
# Main docs: https://robot-wranglers.github.io/compose.mk/signals/

include compose.mk
__main__:
	@# Print usage info and exit.
	$(call log, ${red}USAGE: ${__file__} ls)

ls:; $(call mk.yield, ls $${MAKE_CLI_EXTRA})
