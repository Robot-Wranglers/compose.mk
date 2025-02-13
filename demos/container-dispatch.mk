# demos/container-dispatch.mk: 
#   Demonstrates the container dispatch idiom.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/container-dispatch.mk

# Squash the default noisy output, then override 
# the default goal and include compose.mk primitives
MAKEFLAGS=-sS --warn-undefined-variables
include compose.mk

.DEFAULT_GOAL := demo

$(eval $(call compose.import, ▰, TRUE, tests/docker-compose.yml))

# New target declaration that we can use to run stuff inside 
# a `debian` container mentioned in the external compose file.  
# The syntax/namespace conventions below are configured 
# by the `compose.import` call we used above.
demo: ▰/debian/self.demo

# Displays platform info to show where target is running.
# Since this target is intended to be private, we will 
# prefix "self" to indicate it's intended to be run on 
# containers and not on the host.
self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
