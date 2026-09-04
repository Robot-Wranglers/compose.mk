#!/usr/bin/env -S make -f
#
# inlined-dockerfile.mk:
#   Inlining a Dockerfile, 
#   building it, then working with the container.
#
# USAGE: ./demos/inlined-dockerfile.mk

include compose.mk

# Minimal inlined dockerfile.  
# You can install anything or nothing here, but let's 
# have the minimal stuff that's required for using target dispatch.
define Dockerfile.my_container
FROM ${IMG_ALPINE_BASE:-alpine:3.21.2}
RUN apk add -q --update --no-cache coreutils build-base bash
endef

# After build, image is always at 'compose.mk:<def_name>'.
# This "absolute" name is expected by `docker.*` targets, 
# but the prefix is implied for `mk.docker.*`.
inlined_img=compose.mk:my_container

# Entrypoint.  Ensures the container is built, then runs all the tests.
__main__: Dockerfile.build/my_container flux.star/test

test.1.image_created_and_available:
	$(call log.test, Image is created and available to docker)
	docker image inspect ${inlined_img} > /dev/null
	docker run --entrypoint sh ${inlined_img} -x -c "true" > /dev/null

self.demo.dispatch:
	printf "Running inside the inlined-container:\n"
	uname -a

test.2.docker.dispatch:
	$(call log.test, Expects image prefix & accepts targets)
	img=${inlined_img} ${make} docker.dispatch/self.demo.dispatch

test.3.docker.run.sh:
	$(call log.test, Low-level access to container)
	entrypoint=sh cmd='-c "pwd"' \
		img=${inlined_img} ${make} docker.run.sh 
	
test.4.build.cache_busting:
	$(call log.test, Caching by default. Pass force=1 to override)
	force=1 ${make} Dockerfile.build/my_container

test.5.quiet_build:
	$(call log.test, Dockerfile.build silent by default. Pass quiet=0 to override)
	quiet=0 force=1 ${make} Dockerfile.build/my_container

test.6.docker.lambda.target:
	$(call log.test, Builds/runs Dockerfile in 1 step with docker.lambda)
	cmd='pwd' ${make} docker.lambda/my_container