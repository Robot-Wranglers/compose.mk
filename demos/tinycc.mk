#!/usr/bin/env -S make -f
# demos/tinycc.mk: 
#   Demonstrating polyglots and running as first-class objects in `compose.mk`, .
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/tinycc.mk

include compose.mk

define Dockerfile.tcc 
FROM ${IMG_DEBIAN_BASE:-debian:bookworm-slim}
RUN apt-get update -qq; apt-get install -qq -y tcc
endef 

define hello_world 
#include <stdio.h>
int main() {
    printf("Hello, World from TinyCC!\n");
    return 0;
}
endef

tcc.interpreter/%:
	@# The tcc interpreter, runs the given tmp file as a script. 
	@# This tool insists on '.c' file extensions and won't run otherwise,
	@# so this shim can't rely on usual default cleanup for input tmp file.
	mv ${*} ${*}.c 
	cmd='tcc -run ${*}.c' ${make} mk.docker/tcc
	rm ${*}.c

# Declare the code-block as an object, bind it to the interpreter.
$(eval $(call compose.import.code, hello_world, tcc.interpreter))

# Use our new scaffolded targets for `preview` and `run`
__main__: Dockerfile.build/tcc hello_world.preview hello_world.run