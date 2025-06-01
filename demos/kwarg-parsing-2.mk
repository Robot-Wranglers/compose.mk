#!/usr/bin/env -S make -f
# Building on demos/structured-io.mk to demonstrate parsing structured arguments.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/kwarg-parsing-2.mk

include compose.mk

# Or pass it from the command line..
export shape?=circle

__main__:
	$(call bind.args.from_env, shape=default color=blue) \
	&& printf "shape=$${shape} color=$${color}\n"
