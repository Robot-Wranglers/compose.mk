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

# Squash the default noisy output, then override 
# the default goal and include compose.mk primitives
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := platform.setup

include compose.mk

# Import terraform/ansible targets from compose file services 
$(eval $(call compose.import, ▰, TRUE, demos/docker-compose.platform.yml))

# Map targets to containers.  A public, top-level target. 
platform.setup: ▰/terraform/self.infra.setup ▰/ansible/self.app.setup

# Simulate the setup tasks for app and infrastructure.
# We use the `self.` prefix to indicate these targets are "private",
# and that they should not run from the host.
self.infra.setup:
	echo '{"event":"doing things in terraform container", "log":"infra setup done", "metric":123}'
self.app.setup:
	echo '{"event":"doing things in ansible container", "log":"app setup done", "metric":123}'