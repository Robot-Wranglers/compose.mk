#!/usr/bin/env -S make -f
#
# container-dispatch-min.mk:
#   The most minimal container-dispatch example (import a compose file,
#   then dispatch a target into one of its services).
#
# USAGE: ./demos/container-dispatch-min.mk

include compose.mk
$(call compose.import, file=demos/data/docker-compose.yml)

demo: debian.dispatch/self.demo
self.demo:
	@# Note: This target in the container.
	source /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v

__main__: demo