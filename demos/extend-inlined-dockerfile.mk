#!/usr/bin/env -S make -f
# demos/extend-inlined-dockerfile.mk: 
#   Demonstrates extending an inlined container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/extend-inlined-dockerfile.mk

include demos/inlined-dockerfile.mk
.DEFAULT_GOAL := demo.container.extension

# Minimal inlined dockerfile.  
# This is building on the one defined in `inlined-dockerfile.mk`
define Dockerfile.demo.extend.container
FROM compose.mk:demo_dockerfile
RUN echo hello-docker
endef

# Wrapper target that's using the container.
# This basically sets the container-build as a pre-req,
# so that within the body we can assume the base image exists.
demo.container.extension: Dockerfile.build/demo_dockerfile Dockerfile.build/demo.extend.container
	$(call log.test_case, Working with the image directly, note the 'compose.mk' prefix)
	docker image inspect compose.mk:demo.extend.container > /dev/null
	docker run -it --entrypoint sh compose.mk:demo.extend.container -x -c "true" > /dev/null
	
	$(call log.test_case, Working with compose.mk builtins omits prefix \
		and can dispatch targets to run inside the new image)
	img=demo.extend.container ${make} mk.docker.dispatch/self.demo.container.extension
	
	$(call log.test_case, Add the prefix explicitly, and you can \
		use `docker.run` instead of private `.docker.run`)
	img=compose.mk:demo.extend.container ${make} docker.dispatch/self.demo.container.extension
	
	$(call log.test_case, Subsequent runs will use the cached image.  \
		Pass 'force' to work around this.)
	force=1 ${make} Dockerfile.build/demo.extend.container

self.demo.container.extension:
	echo "Testing target from inside the extended-container"
	uname -a