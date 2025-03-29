#!/usr/bin/env -S make -f
# demos/double-dispatch.mk: 
#   Demonstrates the container dispatch idiom using "namespace" style invocation.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/double-dispatch.mk 


include compose.mk

$(eval $(call compose.import, demos/data/docker-compose.yml, ▰))

# User-facing top-level default target, with two dependencies
__main__: ▰/debian/self.demo ▰/alpine/self.demo

# Displays platform info to show where target is running.
# Since this target is intended to be private, we will 
# prefix "self" to indicate it should not run on host.
self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v