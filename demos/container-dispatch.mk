#!/usr/bin/env -S make -f
# demos/container-dispatch.mk: 
#   Demonstrates the container dispatch idiom.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   USAGE: ./demos/container-dispatch.mk

include compose.mk

# Import all the services in the compose file, 
# including the "debian" container, into the root namespace
$(call compose.import, file=demos/data/docker-compose.yml)

# Basic dispatch style: Run `self.demo` target in the debian container
__main__: debian.dispatch/self.demo

# Target that's actually used with dispatch.  This runs inside the container.
# Using a prefix like `self` or `.` is just convention,  but it helps to show
# this is considered "private", and not intended to be used from the top
self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
