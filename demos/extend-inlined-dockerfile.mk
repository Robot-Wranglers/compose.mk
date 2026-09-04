#!/usr/bin/env -S make -f
#
# extend-inlined-dockerfile.mk: Extending an inlined container.
#
# USAGE: ./demos/extend-inlined-dockerfile.mk

include demos/inlined-dockerfile.mk

# Inlined dockerfile, extending the one defined in `inlined-dockerfile.mk`
define Dockerfile.container_extension
FROM compose.mk:my_container
RUN echo hello-docker
endef

__main__: Dockerfile.build/my_container Dockerfile.build/container_extension
	@# Ensures containers are built, then exercises them
	$(call log.test, Working with the image directly, note the 'compose.mk' prefix)
	docker image inspect compose.mk:container_extension > /dev/null
	docker run --entrypoint sh compose.mk:container_extension -x -c "true" > /dev/null

	$(call log.test, Dispatch a target to run inside the new image)
	img=compose.mk:container_extension ${make} docker.dispatch/self.demo_extension
	
	$(call log.test, Subsequent runs will use the cached image.  \
		Pass 'force' to work around this.)
	force=1 ${make} Dockerfile.build/container_extension

self.demo_extension:
	echo "Testing target from inside the extended container"
	uname -a