#!/usr/bin/env -S make -f
# code-objects-3.mk:
#   First-class support for foreign code-blocks in `compose.mk`.
#
# USAGE: ./demos/code-objects.mk

include compose.mk

# Pick an image and interpreter for the language kernel,
# using a target to customize the default interpreter invocation.
python.img=python:3.11-slim-bookworm
my_interpreter/%:
	cmd="python -O -B ${*}" \
		${make} docker.image.run/${python.img}

# Multiple blocks of python code 
define two.py 
import sys 
print(f'hello world, from {sys.version_info}')
for i in range(3):
	print(f"  count{i}")
endef

define one.py 
import sys 
print([sys.platform, sys.argv])
endef


# Bind multiple code blocks, creating scaffolding for each
$(call polyglots.import, pattern=[.]py bind=my_interpreter)

# Test the scaffolded targets 
__main__: one.py two.py 

