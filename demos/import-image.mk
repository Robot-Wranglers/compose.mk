#!/usr/bin/env -S make -f
# demos/import-image.mk: 
#   Demonstrates importing a docker image, then using scaffolded targets
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
# USAGE: demos/import-image.mk
include compose.mk

$(eval $(call compose.import.docker_image, \
	my_image_alias, debian/buildd:bookworm))

__main__:
	${make} my_image_alias.dispatch/flux.ok
	entrypoint=sh cmd='-c "echo hell-world"' ${make} my_image_alias.run
	