# demos/docker-utils.mk: 
#   Demonstrating various small utility functions for working with docker.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/docker-utils.mk

include compose.mk

.DEFAULT_GOAL := demo.docker

demo.docker: 
	
	# show docker version info
	${make} docker.init
	
	# build a Dockerfile to a tag
	tag=testing ${make} docker.from.file/demos/data/Dockerfile
	
	# run an image with a command
	img=testing entrypoint=sh cmd='-c ls' ${make} docker.run.sh
	
	# run a target inside an image
	img=testing ${make} docker.run/flux.ok