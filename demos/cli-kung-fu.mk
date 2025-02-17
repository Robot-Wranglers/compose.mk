# demos/cli-kung-fu.mk: 
#   Minimal demo for the embedded TUI.  See docs for more discussion.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
#   USAGE: make -f demos/cli-kung-fu
.DEFAULT_GOAL := demo.fu

include compose.mk

# Top-level / public entrypoint.
demo.fu: 
	find demos | ${make} flux.each/show_arg 
	
show_arg/%:; echo ${*}
	