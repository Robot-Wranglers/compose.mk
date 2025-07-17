#!/usr/bin/env -S make -f
# Demonstrates inlining a Dockerfile, 
# building it, then working with the container.
#
# Part of the `compose.mk` repo, runs as part of the test-suite.
#
# USAGE: ./demos/inlined-dockerfile.mk

include compose.mk

# Minimal inlined dockerfile.  
# You can install anything or nothing here, but let's 
# have the minimal stuff that's required for using target dispatch.
define Dockerfile.demo_dockerfile
FROM ${IMG_ALPINE_BASE:-alpine:3.21.2}
RUN apk add -q --update --no-cache coreutils build-base bash procps-ng
endef

# After build, image is always at 'compose.mk:<def_name>'.
# This "absolute" name is expected by `docker.*` targets, 
# but the prefix is implied for `mk.docker.*`.
inlined_img=compose.mk:demo_dockerfile

# Entrypoint.  Ensures the container is built, then runs all the tests.
__main__: Dockerfile.build/demo_dockerfile flux.star/test

test.1.image_created_and_available:
	$(call log.test, Image is created and available to docker)
	docker image inspect ${inlined_img} > /dev/null
	docker run --entrypoint sh ${inlined_img} -x -c "true" > /dev/null

test.2.mk.docker.dispatch:
	$(call log.test, Omits image prefix & does target-dispatch)
	img=demo_dockerfile ${make} mk.docker.dispatch/self.demo.dispatch
self.demo.dispatch:
	printf "Running inside the inlined-container:\n"
	uname -a

test.3.docker.dispatch:
	$(call log.test, Expects image prefix & accepts targets)
	img=${inlined_img} ${make} docker.dispatch/self.demo.dispatch

test.4.docker.run.sh:
	$(call log.test, Low-level access to container)
	entrypoint=sh cmd='-c "pwd"' \
		img=${inlined_img} ${make} docker.run.sh 
	
test.5.build.cache_busting:
	$(call log.test, Caching by default. Pass force=1 to override)
	force=1 ${make} Dockerfile.build/demo_dockerfile

test.6.quiet_build:
	$(call log.test, Dockerfile.build silent by default. Pass quiet=0 to override)
	quiet=0 force=1 ${make} Dockerfile.build/demo_dockerfile

test.7.docker.lambda.target:
	$(call log.test, Builds/runs Dockerfile in 1 step with docker.lambda)
	cmd='pwd' ${make} docker.lambda/demo_dockerfile