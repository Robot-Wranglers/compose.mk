# demos/container-dispatch.mk: 
#   Demonstrates the container dispatch idiom.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/container-dispatch.mk

include compose.mk
.DEFAULT_GOAL := demo

# Import the whole compose file (including "debian" container)
$(eval $(call compose.import, ▰, TRUE, demos/data/docker-compose.yml))

# Basic dispatch style: 
#   This runs the "self.demo" target inside the debian container
demo: debian.dispatch/self.demo

# Target that's actually used with dispatch.  This runs inside the container.
# Using a prefix like `self` or `.` is just convention,  but it helps to indicate
# this is considered "private", and not intended to be used from the top
self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
