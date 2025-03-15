#!/usr/bin/env -S make -f
# demos/container-dispatch.mk: 
#   Demonstrates the container dispatch idiom.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/container-dispatch.mk

include compose.mk
.DEFAULT_GOAL := __main__

# Import all the services in the compose file, including the 
# "debian" container, into the root namespace
$(eval $(call compose.import, demos/data/docker-compose.yml))

# Basic dispatch style: 
#   This runs the "self.demo" target inside the debian container
__main__: debian.dispatch/self.demo

# Target that's actually used with dispatch.  This runs inside the container.
# Using a prefix like `self` or `.` is just convention,  but it helps to indicate
# this is considered "private", and not intended to be used from the top
self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
