# demos/inlined-dockerfile.mk: 
#   A minimal demo embedding a Dockerfile into a Makefile and working with the container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/inlined-dockerfile.mk
include compose.mk
.DEFAULT_GOAL := demo.dockerfile

# Minimal inlined dockerfile.  You can install anything 
# or nothing here, but let's have the minimal stuff 
# that's required for using target dispatch.
define Dockerfile.demo_dockerfile
FROM alpine
RUN apk add --update --no-cache coreutils alpine-sdk bash procps-ng
endef

# Top-level entrypoint.  The initial `docker.from.def` ensures that 
# the container is built first, so all tests can assume the image exists.
demo.dockerfile: docker.from.def/demo_dockerfile
	$(call log.test.case, docker.from.def creates an image and image is available to docker)
	docker image inspect compose.mk:demo_dockerfile > /dev/null
	docker run -it --entrypoint sh compose.mk:demo_dockerfile -x -c "true" > /dev/null

	$(call log.test.case, mk.docker.run omits image prefix and does target-dispatch)
	img=demo_dockerfile ${make} mk.docker.run/self.demo.dockerfile

	$(call log.test.case, docker.run requires image prefix and does target-dispatch)
	img=compose.mk:demo_dockerfile ${make} docker.run/self.demo.dockerfile

	$(call log.test.case, docker.run.sh gives low-level access to container)
	entrypoint=sh cmd='-c "ls"' img=compose.mk:demo_dockerfile make docker.run.sh 
	
	$(call log.test.case, docker.from.def caches by default-- pass force=1 to override)
	force=1 ${make} docker.from.def/demo_dockerfile

	$(call log.test.case, docker.from.def silent by default-- pass quiet=0 to override)
	quiet=0 force=1 ${make} docker.from.def/demo_dockerfile

	$(call log.test.case, docker.lambda builds/runs a def in one step with no tag references)
	entrypoint=sh cmd='-c "ls"' ${make} docker.lambda/demo_dockerfile
	
	$(call log.test.case, docker.lambda also works as a macro)
	$(call docker.lambda, demo_dockerfile, sh -c ls)

# Helper used for dispatch
self.demo.dockerfile:
	echo "Testing target from inside the inlined-container"
	uname -a

