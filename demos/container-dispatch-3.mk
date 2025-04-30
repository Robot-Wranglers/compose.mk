#!/usr/bin/env -S make -f
# demos/container-dispatch-3.mk: 
#   Demonstrates the container dispatch idiom using "namespace" style invocation.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   USAGE: ./demos/container-dispatch-3.mk

include compose.mk

$(eval $(call compose.import.as, ▰, demos/data/docker-compose.build-tools.yml))
$(eval $(call compose.import.as, 🜹, demos/data/docker-compose.docs-tools.yml))

__main__: build docs 

build: ▰/golang/self.code.gen
self.code.gen:
	echo "pretending to do stuff with golang"

docs: 🜹/latex/self.docs.gen
self.docs.gen:
	echo "pretending to do stuff with LaTeX"

