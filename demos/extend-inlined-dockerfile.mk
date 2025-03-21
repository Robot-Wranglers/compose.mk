#!/usr/bin/env -S make -f
# demos/extend-inlined-dockerfile.mk: 
#   Demonstrates extending an inlined container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/extend-inlined-dockerfile.mk

include demos/inlined-dockerfile.mk

# Inlined dockerfile, extending the one defined in `inlined-dockerfile.mk`
define Dockerfile.container_extension
FROM compose.mk:demo_dockerfile
RUN echo hello-docker
endef

# Ensures containers are built, then exercises them
__main__: Dockerfile.build/demo_dockerfile Dockerfile.build/container_extension
	$(call log.test_case, Working with the image directly, note the 'compose.mk' prefix)
	docker image inspect compose.mk:container_extension > /dev/null
	docker run --entrypoint sh compose.mk:container_extension -x -c "true" > /dev/null
	
	$(call log.test_case, Working with compose.mk builtins omits prefix \
		and can dispatch targets to run inside the new image)
	img=container_extension ${make} mk.docker.dispatch/self.demo_extension
	
	$(call log.test_case, Add the prefix explicitly, and you can \
		use `docker.run` instead of private `.docker.run`)
	img=compose.mk:container_extension ${make} docker.dispatch/self.demo_extension
	
	$(call log.test_case, Subsequent runs will use the cached image.  \
		Pass 'force' to work around this.)
	force=1 ${make} Dockerfile.build/container_extension

self.demo_extension:
	echo "Testing target from inside the extended container"
	uname -a