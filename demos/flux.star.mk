#!/usr/bin/env -S make -f
# Demonstrates pattern matching on target-names.
# Part of the `compose.mk` repo, runs as part of the test-suite.
# USAGE: ./demos/flux.star.mk

include compose.mk

__main__: flux.star/test

test.1:; echo 1
test.2:; echo 2
test.3:; echo 3
no.match:; echo never called