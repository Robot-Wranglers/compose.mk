#!/usr/bin/env -S make -f
# Demonstrating idiom for container-agnostic script dispatch,
# where the target always run from the container, but does not 
# care where it is called from.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
# USAGE: ./demos/container-agnostic.mk

include compose.mk

$(eval $(call compose.import, demos/data/docker-compose.yml))

__main__: test.agnostic_script

# Define a target, mentioning a container, and define the
# script; it should have exactly the same name as the target
my_script:; $(call containerized.script, debian)
define my_script
echo hello container `hostname`
endef

# Test that target still works whether it is called from 
# the host or from a container.
test.agnostic_script:
	$(call log.test, my_script works from host)
	${make} my_script
	$(call log.test, my_script works from container)
	${make} debian.dispatch/my_script
