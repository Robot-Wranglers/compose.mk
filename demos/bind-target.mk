#!/usr/bin/env -S make -f
# Demonstrating idiom for container-agnostic target dispatch,
# where the target always run from the container, but does not 
# care where it is called from.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
#
# USAGE: ./demos/bind-target-2.mk

include compose.mk
$(call compose.import, file=demos/data/docker-compose.yml)


# Decorator-style idiom.  
# This binds together a container, a "public" target, 
# and a "private" target.  The public-target becomes the main interface
# while the private target runs inside the named container.
my_target:; $(call compose.bind.target, debian)
self.my_target:
	echo hello container `hostname`

# Test that target still works, no matter where it's called from.
__main__:
	${make} my_target | grep "hello container"
	${make} debian.dispatch/my_target  | grep "hello container"