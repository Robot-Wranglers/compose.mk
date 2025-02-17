# demos/docker-utils.mk: 
#   Demonstrating various small utility functions for working with docker.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/docker-utils.mk

include compose.mk

.DEFAULT_GOAL := demo.docker

demo.docker: docker.init