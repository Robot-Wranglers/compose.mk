#!/usr/bin/env -S make -f
# structured-io.mk:
#   Target input/output using JSON.
#
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