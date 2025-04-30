#!/usr/bin/env -S make -f
# demos/partials.mk: 
#   Demonstrates implementing something close to partial functions with compose.mk.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/partials.mk

include compose.mk

adder/%:
	@# Unpacks the comma-separated arguments and adds them together.
	expr $(call mk.unpack_arg, 1) + $(call mk.unpack_arg, 2)

add7/%:
	@# Defining a partial function explicitly, nothing fancy
	${make} adder/7,${*}

# Dynamic target creation with __flux.partial__.
# This creates `add2` target dynamically
$(call __flux.partial__, add2, adder, 2)

__main__: adder/1,3 add7/3 add2/10