#!/usr/bin/env -S make -f
# Demonstrates importing a docker image, then using scaffolded targets
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
# USAGE: demos/import-image.mk

include compose.mk

# Import a stack image 
$(call docker.import, namespace=debian img=debian/buildd:bookworm)

# Import an image described by a local Dockerfile
$(call docker.import, namespace=mycontainer file=demos/data/Dockerfile)

__main__: test.stock_image test.local_image 

# Test dispatch and low-level targets for locally defined image
# Note that we have to build it before we can use it
test.local_image: mycontainer.build 
	${make} mycontainer.dispatch/flux.ok 
	entrypoint=sh cmd='-c "echo hello-world"' ${make} mycontainer

# Test dispatch and low-level targets inside for stock image
test.stock_image: 
	${make} debian.dispatch/flux.ok 
	entrypoint=sh cmd='-c "echo hello-world"' ${make} debian

	