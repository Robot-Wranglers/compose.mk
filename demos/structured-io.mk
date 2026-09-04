#!/usr/bin/env -S make -f
#
# structured-io.mk: Target input/output using JSON.
#
# USAGE: ./demos/structured-io.mk

include compose.mk

emit: 
	@# Emit/consume JSON with `compose.mk` macros.  
	@# Uses native tools if they are available, falling back to docker.
	${jb} key=val

consume:
	${stream.stdin} | ${jq} .key

__main__:
	@# Exercise the pipeline
	${make} emit | ${make} consume