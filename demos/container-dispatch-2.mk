#!/usr/bin/env -S make -f
#
# container-dispatch-2.mk:
#   The container dispatch idiom using "namespace" style invocation.
#
# USAGE: ./demos/container-dispatch-2.mk

include compose.mk

# Import the whole compose file (including "debian" container)
$(call compose.import, file=demos/data/docker-compose.yml namespace=▰)

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
