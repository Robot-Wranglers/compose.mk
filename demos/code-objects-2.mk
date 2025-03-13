#!/usr/bin/env -S make -f
# demos/code-objects-2.mk: 
#   Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/code-objects-2.mk

include compose.mk
.DEFAULT_GOAL := demo.python

# First we pick an image and interpreter for the language kernel.
# Here, iex can work too, but there are minor differences.
python.img=$${IMG_PYTHON_BASE:-python:3.11-slim-bookworm}
python.interpreter=python 

# Bind the docker image / entrypoint to a target and
# Create a unary target for an elixir interpreter, accepting a filename.
python:; ${docker.image.run}/${python.img},${python.interpreter}
python.interpreter/%:; ${docker.curry.command}/python

# Now define several chunks of elixir code
define hello_world_1.py 
print('hello world 1')
endef

define hello_world_2.py 
print('hello world 2')
endef

# Import the code-block, creating additional target scaffolding for it.
$(eval $(call compose.import.code, [.]py, python.interpreter))

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
demo.python: hello_world_1.py.preview hello_world_1.py.run hello_world_2.py.run

