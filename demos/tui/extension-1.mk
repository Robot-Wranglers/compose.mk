#!/usr/bin/env -S make -f
# demos/tui/extension-1.mk:
#   Minimal demo for extending the embedded TUI.  See docs for more discussion.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.
#
#   USAGE: ./demos/tui/extension-1.mk

include compose.mk

# Look, a nixos container with yazi 
# https://yazi-rs.github.io/docs/installation/#nix
define Dockerfile.yazi 
FROM nixos/nix
RUN nix-channel --update && nix-env -iA nixpkgs.yazi
ENTRYPOINT ["yazi"]
endef

# Look, this maps a container invocation to a target
# This works the way you'd expect without the TUI too, 
# so we leave it as a public target.
widget.yazi:
	cmd="demos/" tty=1 \
		${make} docker.image.run/compose.mk:yazi

# Main top-level / public entrypoint.
# Extending the TUI usually starts with a call to `tux.open`, 
# including basic information about the backend `tmux` session.
# We opt for horizontal layout, and instantiate 2 of the yazi-widgets
__main__: \
	docker.from.def/yazi \
	tux.open.horizontal/widget.yazi,widget.yazi