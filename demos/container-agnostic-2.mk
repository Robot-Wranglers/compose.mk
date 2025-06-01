#!/usr/bin/env -S make -f
# Demonstrating idiom for container-agnostic target dispatch,
# where the target always run from the container, but does not 
# care where it is called from.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
# USAGE: ./demos/container-agnostic-2.mk

include compose.mk

$(eval $(call compose.import, demos/data/docker-compose.yml))

__main__: test.agnostic_target

# Define a "public" target mentioning a container, and a 
# "private"target which has the same name but uses a "." prefix.
my_target:; $(call containerized.target, debian)
.my_target:
	echo hello container `hostname`

# Test that target still works whether it is called from 
# the host or from a container.
test.agnostic_target:
	$(call log.test, my_target works from host)
	${make} my_target
	$(call log.test, my_target works from container)
	${make} debian.dispatch/my_target