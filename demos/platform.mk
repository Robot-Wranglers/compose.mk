#!/usr/bin/env -S make -f
# platform.mk:
#   A way to organize platform lifecycle automation with `compose.mk`.
#   We use namespace-style dispatch here to run commands in docker-compose managed 
#   containers, and use `compose.mk` workflows to to describe data-flow.
#
# USAGE: ./demos/platform.mk

include compose.mk

__main__: platform.setup.basic

# Import the platform compose file.
# This generates target-scaffolding for terraform and ansible, 
# and sets up syntactic sugar for target-dispatch under the "▰" namespace
$(call compose.import.as, \
	namespace=▰ file=demos/data/docker-compose.platform.yml)

# Implementing a fake setup for platform bootstrap:
#   1. Infrastructure is configured by the terraform container, 
#   2. Application is configured by the ansible container,
#   3. Both tasks emit JSON events (simulating terraform state output, etc)

# Map targets to containers.  A public, top-level target. 
platform.setup.basic: \
	▰/terraform/self.infra.setup \
	▰/ansible/self.app.setup

# Simulate the setup tasks for app and infrastructure.
# Note usage of `jb` to emit JSON, and `self.` prefix to hint 
# these targets are "private" / not intended to run from the host. 
self.infra.setup:
	@# pretending to use terraform..
	${jb} log="infra setup done" metric=123 \
		event="terraform container task" 

self.app.setup:
	@# pretending to use ansible..
	${jb} log="app setup done" metric=456 \
		event="ansible container task"