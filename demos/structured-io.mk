#!/usr/bin/env -S make -f
# demos/structured-io.mk: 
#   Show output/input using JSON.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#   USAGE: ./demos/structured-io.mk

include compose.mk

# Emit/consume JSON with `compose.mk` macros.  
# Uses native tools if they are available, falling back to docker.
emit: 
	${jb} key=val

consume:
	${stream.stdin} | ${jq} .key

__main__:
	${make} emit | ${make} consume
