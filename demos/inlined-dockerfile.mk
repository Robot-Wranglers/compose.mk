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
RUN echo Building container spec from inlined dockerfile
RUN apk add --update --no-cache coreutils alpine-sdk bash procps-ng
endef

# Wrapper target that's using the container.
# Here `docker.from.def` sets the container-build as a pre-
# req, so that within the target body we can assume 
# the base image already exists.
demo.dockerfile: docker.from.def/demo_dockerfile
	# Working with the image directly, note the 'compose.mk' prefix.
	docker image inspect compose.mk:demo_dockerfile > /dev/null
	docker run -it --entrypoint sh compose.mk:demo_dockerfile -x -c "true" > /dev/null

	# Working with compose.mk builtins omits prefix, 
	# and can do dispatch targets to run inside the new image
	img=demo_dockerfile make mk.docker.run/self.demo.dockerfile

	# Add the prefix explicitly, and you can use `docker.run` instead
	img=compose.mk:demo_dockerfile make docker.run/self.demo.dockerfile
	entrypoint=sh cmd='-c "ls"' img=compose.mk:demo_dockerfile make docker.run.sh 
	
	# Subsequent runs will use the cached image.  
	# Pass 'force' to work around this.
	force=1 make docker.from.def/demo_dockerfile

self.demo.dockerfile:
	echo "Testing target from inside the inlined-container"
	uname -a

