#!/usr/bin/env -S make -f
# Demonstrates importing a docker image, then using scaffolded targets
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
# USAGE: demos/import-image.mk

include compose.mk

$(call docker.import, namespace=debian img=debian/buildd:bookworm)

__main__: test.dispatch test.low_level_runner

test.dispatch: debian.dispatch/flux.ok

test.low_level_runner:
	entrypoint=sh cmd='-c "echo hello-world"' ${make} debian