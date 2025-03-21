#!/usr/bin/env -S make -f
# demos/container-dispatch-2.mk: 
#   Demonstrates the container dispatch idiom using "namespace" style invocation.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/container-dispatch-2.mk

include compose.mk

# Import the whole compose file (including "debian" container)
$(eval $(call compose.import, demos/data/docker-compose.yml, ▰))

# Namespaced dispatch style:
#   This uses namespacing syntax that was configured as part 
#   of the `compose.import` call, and you can think of it as 
#   a more explicit "absolute path" to dispatch.  To avoid 
#   collisions, you can use this to structure calls to 
#   multiple containers in multiple files.
__main__: ▰/debian/self.demo

self.demo:
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
