#!/usr/bin/env -S make -f
# Minimal demo for extending the embedded TUI.  See docs for more discussion.
#
# USAGE: ./demos/tui/extension-1.mk

include compose.mk

# A nixos container with yazi.
# https://yazi-rs.github.io/docs/installation/#nix
define Dockerfile.yazi
FROM nixos/nix
RUN nix-channel --update && nix-env -iA nixpkgs.yazi
ENTRYPOINT ["yazi"]
endef

widget.yazi:
	@# Maps the yazi container invocation onto a target.  This works the way
	@# you'd expect without the TUI too, so we leave it a public target.
	cmd="demos/" tty=1 \
		${make} docker.image.run/compose.mk:yazi

# Main top-level / public entrypoint.
# Extending the TUI usually starts with a call to `tux.open`, 
# including basic information about the backend `tmux` session.
# We opt for horizontal layout, and instantiate 2 of the yazi-widgets
__main__: \
	Dockerfile.build/yazi \
	tux.open.horizontal/widget.yazi,widget.yazi