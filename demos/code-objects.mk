#!/usr/bin/env -S make -f
# demos/code-objects.mk: 
#   Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# USAGE: ./demos/code-objects.mk

include compose.mk
.DEFAULT_GOAL := __main__

# First we pick an image and interpreter for the language kernel.
# Here, iex can work too, but there are minor differences.
python.img=$${IMG_PYTHON_BASE:-python:3.11-slim-bookworm}
python.interpreter=python

# Bind the docker image / entrypoint to a target
python:; ${docker.image.run}/${python.img},${python.interpreter}

# Create a unary target for a python interpreter, accepting a filename.
python.interpreter/%:; ${docker.curry.command}/python

# Now define the python code
define hello_world 
print('hello world')
endef

# Import the code-block, creating additional target scaffolding for it.
$(eval $(call compose.import.code_block, hello_world, python.interpreter))

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
__main__: hello_world.preview hello_world.run

