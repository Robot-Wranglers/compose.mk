#!/usr/bin/env -S ./compose.mk mk.interpret
# demos/interpreter-2.mk: 
#   Demonstrating compose.mk as an alternate interpreter for make.
#   This is mostly used for inheriting signals/supervisors.  
#
# Main docs: https://robot-wranglers.github.io/compose.mk/signals/

include compose.mk

.DEFAULT_GOAL:=__main__

ls:; $(call mk.yield, ls $${MAKE_CLI_EXTRA})

__main__:
	${make} ls -- --help
	this line still wont run, we already yielded execution!