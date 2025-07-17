#!/usr/bin/env -S make -f
# Building on demos/structured-io.mk to demonstrate parsing structured arguments.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/kwarg-parsing.mk

include compose.mk

emit: 
	@# Emit JSON with jb
	${jb} shape=triangle color=red

consume:
	@# Parse data from JSON input with `bind.args.from_json`.
	@# This binds a subset of JSON key/vals as bash variables, 
	@# optionally providing defaults when keys are missing.
	$(call bind.args.from_json, shape color=blue name=default) \
	&& printf "shape=$${shape} color=$${color} name=$${name}\n"

# Equivalent to `make emit | make consume`
__main__: flux.pipeline/emit,consume
