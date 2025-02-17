# demos/tui-extension.mk: 
#   Minimal demo for the embedded TUI.  See docs for more discussion.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
#   USAGE: make -f demos/dashboarding.mk
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := demo.dashboard

include compose.mk

# Top-level / public entrypoint.
# Extending the TUI usually starts with a call to `tux.commander`,
# which includes basic information about the backend `tmux` session.
# We declare the number of panes +  a callback for the layout.
demo.dashboard:
	$(call tux.log, demo.dashboard ${sep} ${dim}Starting demo)
	${make} tux.open/spiral/io.bash,io.bash,target1
	
target1:
	echo hello world

# Private layout callback we referenced above.
# This layout callback is triggered after tmux is already bootstrapped,
# and runs inside the TUI container. From here we a) declare the layout 
# as `.tux.layout.spiral`, and b) declare pane content by calling the
# parametric `.tux.pane/<pane_index>/<make_target>`.  
#
# But what target should we assign to the panes?  For this example, 
# the `io.bash` target is perfect, since it opens an interactive shell.  
# You can use any target, but note that if you assign targets which 
# actually *exit*, then the TUI will exit too and it's not crashing :) 
# .demo.dashboard.layout: 
# 	$(call tux.log, demo.dashboard.layout ${sep} ${dim}Laying out panes)
# 	${make} .tux.layout.spiral \
# 		.tux.pane/0/io.bash \
# 		.tux.pane/1/io.bash 
		
