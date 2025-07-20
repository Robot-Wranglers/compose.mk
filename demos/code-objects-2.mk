#!/usr/bin/env -S make -f
# Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/code-objects.mk

include compose.mk

# Look, it's a python script 
define hello_world.py
import os 
print(f'hello {os.environ["planet"]} {os.environ["index"]}')
endef

# Pick an image and interpreter for the language kernel.
# Uses a stock-image but modifies the default invocation.
python.img=python:3.11-slim-bookworm
my_interpreter/%:
	cmd="python -O -B ${*}" \
		${make} docker.image.run/${python.img}

# Constants we can share with subprocesses or polyglots
export planet=earth
export index=616

# Import the code-block to a specific namespace, 
# creating scaffolding for `run` and `preview`, while 
# passing through certain parts of this environment
$(call polyglot.import, \
	def=hello_world.py bind=my_interpreter \
		namespace=WORLD env='planet index')

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
__main__: WORLD.preview WORLD

