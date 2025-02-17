# demos/tui-extension.mk: 
#   Minimal demo for extending the embedded TUI.  See docs for more discussion.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
#   USAGE: make -f demos/tui-extension.mk

include compose.mk

.DEFAULT_GOAL := demo.dashboard

# Top-level / public entrypoint.
# Extending the TUI usually starts with a call to `tux.commander`,
# which includes basic information about the backend `tmux` session.
# We declare the number of panes +  a callback for the layout.
demo.dashboard:
	$(call tux.log, demo.dashboard ${sep} ${dim}Starting demo)
	${make} tux.open/io.bash,io.bash
	