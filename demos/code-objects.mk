#!/usr/bin/env -S make -f
# demos/code-objects.mk: 
#   Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/code-objects.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
python.img=python:3.11-slim-bookworm
python.interpreter=python

# Now define the python code
define hello_world 
print('hello world')
endef

# Import the code-block, creating additional target scaffolding for it.
$(eval $(call polyglot.bind.container, \
	hello_world, ${python.img}, ${python.interpreter}))

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
__main__: hello_world.preview hello_world.run

