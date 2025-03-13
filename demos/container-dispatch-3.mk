#!/usr/bin/env -S make -f
# demos/container-dispatch-3.mk: 
#   Demonstrates the container dispatch idiom using "namespace" style invocation.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/container-dispatch-2.mk

include compose.mk
.DEFAULT_GOAL := demo.namespaced_dispatch

$(eval $(call compose.import.as, ▰, demos/data/docker-compose.build-tools.yml))
$(eval $(call compose.import.as, 🜹, demos/data/docker-compose.docs-tools.yml))

demo.namespaced_dispatch: build docs 
docs: 🜹/latex/self.docs.gen
build: ▰/golang/self.code.gen

self.docs.gen:
	echo "pretending to do stuff with LaTeX"

self.code.gen:
	echo "pretending to do stuff with golang"
