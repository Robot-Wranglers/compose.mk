#!/usr/bin/env -S ./compose.mk mk.interpret
# demos/interpreter.mk: 
#   Demonstrating compose.mk as an alternate interpreter for make.
#   This is mostly used with extensions that want to inherit signals/supervisors.
#
# Main docs: https://robot-wranglers.github.io/compose.mk/signals/

# NB: explicit include is optional when the shebang sets `compose.mk`
# as the interpreter.  It's good to keep it anyway so the file can work
# as well with `make -f ..`
include compose.mk

ls:; $(call mk.yield, ls $${MAKE_CLI#*ls})

__main__:
	# this line works, but exits afterwards
	${make} ls /var
	
	# lines afterwards will not run.
	this second line never runs!