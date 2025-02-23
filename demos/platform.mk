# demos/platform.mk: 
#   Shows one way to organize platform lifecycle automation.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/platform.mk platform.setup
#
# Implementing a fake setup for platform bootstrap:
#   1. Infrastructure is configured by the terraform container, 
#   2. Application is configured by the ansible container,
#   3. Assume both tasks emit json events (simulating terraform state output, etc)

include compose.mk
.DEFAULT_GOAL := platform.setup

# Import the platform compose file, 
# generating target-scaffolding for terraform and ansible
$(eval $(call compose.import, ▰, TRUE, demos/data/docker-compose.platform.yml))

# Map targets to containers.  A public, top-level target. 
platform.setup: \
	terraform.dispatch/self.infra.setup \
	ansible.dispatch/self.app.setup

# Simulate the setup tasks for app and infrastructure.
# Note usage of `jb` to emit JSON, and `self.` prefix to hint 
# these targets are "private" / not intended to run from the host. 
self.infra.setup:
	${jb} log="infra setup done"  \
		event="terraform container task" metric=123
self.app.setup:
	${jb} log="app setup done" \
		event="ansible container task" metric=456