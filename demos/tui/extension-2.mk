#!/usr/bin/env -S make -f
# extension-2.mk: extend the embedded TUI, building on extension-1's yazi widget --
# adds a web-browser widget, a logo widget, and a `gum`-based task chooser.  See the
# docs for more discussion.  Part of the `compose.mk` repo; runs in the test-suite.
#
# USAGE: ./demos/tui/extension-2.mk

# Pickup where the first extension left off 
include demos/tui/extension-1.mk

# Starts a webbrowser as a widget.
widget.browser:; url='http://www.wikipedia.com' ${make} tux.browser

# Gets an animated gif for use as a widget, just by naming the location.
widget.logo: .tux.widget.img/demos/data/neo2.gif

# A chooser widget using `gum choose` that works with or without `gum`.
# If we're dockerized, getting the choice back from a fake tty is hard, 
# but using the `io.selector` idiom makes it simple.
#
# In this cases the choices are exactly the `task.*` targets below, 
# so we just execute the chosen target, pause, and exit.
widget.choice:
	header="Choose a task to run:" \
	${make} io.selector/self.tasks.list,flux.apply

# Loops the simple choice widget forever
widget.chooser: flux.loopf/widget.choice


# Helper to return the targets matching "task.*" pattern
self.tasks.list: mk.targets.filter/task.

# Fake tasks to populate the chooser. These are only
# placeholders and just print a banner with their name.
task.1st:; label=${@} ${make} io.draw.banner
task.2nd:; label=${@} ${make} io.draw.banner
task.3rd:; label=${@} ${make} io.draw.banner
task.4th:; label=${@} ${make} io.draw.banner
task.5th:; label=${@} ${make} io.draw.banner
task.6th:; label=${@} ${make} io.draw.banner

# Main top-level / public entrypoint.
#
# Extending the TUI usually starts with a call to `tux.open`, 
# including basic information about the backend `tmux` session.
# We opt for horizontal layout, and reference the widgets so far.
widgets:=widget.yazi,widget.browser,widget.chooser,widget.logo
__main__: Dockerfile.build/yazi tux.open.spiral/${widgets}
