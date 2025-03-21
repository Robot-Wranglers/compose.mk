#!/usr/bin/env -S make -f
# demos/code-objects-2.mk: 
#   Demonstrating first-class support for foreign code-blocks in `compose.mk`.
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# USAGE: ./demos/code-objects-2.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
python.img=python:3.11-slim-bookworm
python.interpreter=python 

# Now define several chunks of python code
define hello_world_1.py 
print('hello world 1')
endef

define hello_world_2.py 
print('hello world 2')
endef

# Bind multiple code-blocks, creating additional target scaffolding for each
$(eval $(call polyglots.bind.container, \
	[.]py, ${python.img}, ${python.interpreter}))

# With the new target-scaffolding in place, now we can use it.
# First we preview the code with syntax highlighting, 
# then run the code inside the bound interpreter.
__main__: hello_world_1.py.preview hello_world_1.py.run hello_world_2.py.run

