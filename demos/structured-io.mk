#!/usr/bin/env -S make -f
# Demonstrates target input/output using JSON.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/structured-io.mk

include compose.mk

# Emit/consume JSON with `compose.mk` macros.  
# Uses native tools if they are available, falling back to docker.
emit: 
	${jb} key=val

consume:
	${stream.stdin} | ${jq} .key

# Exercise the pipeline
__main__:
	${make} emit | ${make} consume