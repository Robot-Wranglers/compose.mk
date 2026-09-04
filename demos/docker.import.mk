#!/usr/bin/env -S make -f
#
# docker.import.mk: Importing a docker image, then using scaffolded targets
#
# USAGE: demos/docker.import.mk

include compose.mk

# Import a stock image 
$(call docker.import, namespace=debian img=debian/buildd:bookworm)

# Import an image described by a local Dockerfile
$(call docker.import, namespace=mycontainer file=demos/data/Dockerfile)

__main__: test.stock_image test.local_image 

test.local_image: mycontainer.build 
	@# Test dispatch and low-level targets for locally defined image
	@# Note that we have to build it before we can use it
	${make} mycontainer.dispatch/flux.ok 
	entrypoint=sh cmd='-c "echo hello-world"' ${make} mycontainer

test.stock_image: 
	@# Test dispatch and low-level targets inside for stock image
	${make} debian.dispatch/flux.ok 
	entrypoint=sh cmd='-c "echo hello-world"' ${make} debian

	