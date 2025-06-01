#!/usr/bin/env -S make -f
# Demonstrating binding existing to the environment idioms for container-agnostic script dispatch with 
# compose-file backed tool containers. The target script always runs 
# from the container, but does not care whether it's called from the host,
# or from inside the container.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
#
# USAGE: ./demos/bind-script.mk

include compose.mk

define variable
this is data
on multiple lines
endef

__main__:
	$(call bind.def.to.env, variable, VARIABLE) \
	&& printf "$${VARIABLE}"

