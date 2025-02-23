# demos/tui-extension-2.mk: 
#   Second TUI extension.  This keeps the yazi file-browser from
#   the first version, and adds a target-selector and an animated gif.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
#   USAGE: make -f demos/tui-extension.mk

# Pickup where the first extension left off 
include demos/tui/extension-1.mk
.DEFAULT_GOAL := demo.dashboard2

# Get an animated gif as a widget, just by naming the location.
widget.logo: .tux.widget.img/demos/data/neo2.gif

# Helper to return the targets matching "task.*" pattern
task_list:; ${make} mk.parse.local | grep 'task[.]' | ${stream.nl.to.space}

# Fake tasks to populate the chooser.. these will just print their own name, but could do anything
task.1st:; label=${@} ${make} io.gum.style
task.2nd:; label=${@} ${make} io.gum.style
task.3rd:; label=${@} ${make} io.gum.style
task.4th:; label=${@} ${make} io.gum.style
task.5th:; label=${@} ${make} io.gum.style
task.6th:; label=${@} ${make} io.gum.style

# A chooser widget using `gum choose` that works with or without `gum`.
# If we're dockerized, getting the choice back from a fake tty is hard, 
# but using the `choices .. io.get.choice .. chosen` idiom makes it simple.
#
# In this cases the choices are exactly the fake tasks above, 
# so we just execute the chosen target, pause, and exit.
widget.choice:
	clear; header="Choose a task to run:" \
	&& choices=`${make} task_list` \
	&& ${io.get.choice} && ${make} $${chosen} io.wait/2

# Loops the simple choice widget forever
widget.chooser: flux.loopf/widget.choice

# Main top-level / public entrypoint.
# Extending the TUI usually starts with a call to `tux.open`, 
# including basic information about the backend `tmux` session.
# We opt for horizontal layout, and reference the widgets so far.
demo.dashboard2: docker.from.def/yazi
	$(call tux.log, demo.dashboard ${sep} ${dim}Starting demo)
	${make} tux.open.spiral/widget.yazi,widget.logo,widget.chooser
	