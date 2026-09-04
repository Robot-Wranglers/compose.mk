#!/usr/bin/env -S make -f
#
# container-dispatch-3.mk:
#   The container dispatch idiom using "namespace" style invocation.
#
# USAGE: ./demos/container-dispatch-3.mk

include compose.mk

$(call compose.import.as, namespace=▰ \
	file=demos/data/docker-compose.build-tools.yml)
$(call compose.import.as, namespace=🜹 \
	file=demos/data/docker-compose.docs-tools.yml)

__main__: build docs 

build: ▰/golang/self.code.gen
self.code.gen:
	echo "pretending to use golang"

docs: 🜹/latex/self.docs.gen
self.docs.gen:
	echo "pretending to use LaTeX"

