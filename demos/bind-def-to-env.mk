#!/usr/bin/env -S make -f
# bind-def-to-env.mk:
#   Binding existing to the environment idioms for container-agnostic script dispatch with 
#   compose-file backed tool containers. The target script always runs 
#   from the container, but does not care whether it's called from the host,
#   or from inside the container.
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

