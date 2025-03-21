#!/usr/bin/env -S make -f
# demos/inlined-dockerfile.mk: 
#   Demonstrates inlining a Dockerfile, building it, then working with the container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
#   USAGE: ./demos/inlined-dockerfile.mk
include compose.mk
.DEFAULT_GOAL := __main__

# Entrypoint.  Ensures the container is built, then runs all the tests.
__main__: Dockerfile.build/demo_dockerfile flux.star/test

# A minimal inlined dockerfile.  You can install anything or nothing here,
# but let's have the minimal stuff that's required for using target dispatch.
define Dockerfile.demo_dockerfile
FROM alpine
RUN apk add -q --update --no-cache coreutils build-base bash procps-ng
endef

test.1.image_created_and_available:
	$(call log.test_case, image is created and available to docker)
	docker image inspect compose.mk:demo_dockerfile > /dev/null
	docker run --entrypoint sh compose.mk:demo_dockerfile -x -c "true" > /dev/null

test.2.mk.docker.dispatch:
	$(call log.test_case, mk.docker.dispatch omits image prefix & does target-dispatch)
	img=demo_dockerfile ${make} mk.docker.dispatch/self.demo.dispatch
self.demo.dispatch:
	echo "Testing target from inside the inlined-container: `uname -a`"

test.3.docker.dispatch:
	$(call log.test_case, docker.dispatch requires image prefix & does target-dispatch)
	img=compose.mk:demo_dockerfile ${make} docker.dispatch/self.demo.dispatch

test.4.docker.run.sh:
	$(call log.test_case, docker.run.sh gives low-level access to container)
	entrypoint=sh cmd='-c "pwd"' img=compose.mk:demo_dockerfile ${make} docker.run.sh 
	
test.5.cache_busting:
	$(call log.test_case, Dockerfile.build caches by default. Pass force=1 to override)
	force=1 ${make} Dockerfile.build/demo_dockerfile

test.6.quiet_build:
	$(call log.test_case, Dockerfile.build silent by default. Pass quiet=0 to override)
	quiet=0 force=1 ${make} Dockerfile.build/demo_dockerfile

test.7.docker.lambda.target:
	$(call log.test_case, docker.lambda builds/runs Dockerfile in 1 step w/o tag)
	cmd='pwd' ${make} docker.lambda/demo_dockerfile
	

