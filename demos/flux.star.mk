#!/usr/bin/env -S make -f
# flux.star.mk:
#   Pattern matching on target-names.
#
# USAGE: ./demos/flux.star.mk

include compose.mk

__main__: flux.star/test

test.1:; echo 1
test.2:; echo 2
test.3:; echo 3
no.match:; echo never called