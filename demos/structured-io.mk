#!/usr/bin/env -S make -f
# demos/structured-io.mk: 
#   Show output/input using JSON.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#   USAGE: ./demos/structured-io.mk

include compose.mk
.DEFAULT_GOAL := __main__

__main__:
	${make} emit | ${make} consume

# Emit/consume JSON with `compose.mk` macros.  
# Uses native tools if they are available, falling back to docker.
emit: 
	${jb} key=val

consume:
	${stream.stdin} | ${jq} .key