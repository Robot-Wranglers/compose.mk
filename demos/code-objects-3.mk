#!/usr/bin/env -S make -f
# demos/code-objects.mk: 
#   Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# USAGE: ./demos/code-objects.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
python.img=python:3.11-slim-bookworm

# Now define the python code
define hello_world 
print('hello world')
endef

my.interpreter/%:
	cmd="python -O -B ${*}" \
		${make} docker.image.run/${python.img}

# Import the code-block, creating additional target scaffolding for it.
$(eval $(call polyglot.bind.target, hello_world, my.interpreter))

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
__main__: hello_world.preview hello_world.run

