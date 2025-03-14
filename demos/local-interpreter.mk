#!/usr/bin/env -S make -f
# demos/local-interpreter.mk: 
#
#   Demos make-targets in foreign languages, without a container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/local-interpreter.mk

include compose.mk
.DEFAULT_GOAL := demo.python

# Look, here's a simple python script 
define Python.demo
import sys
print('python world')
print('dollar signs are safe: $')
endef

# Minimal boilerplate to run the script, using a specific interpreter (python3).
# No container here, so this requires that the interpreter is actually available.
demo.python: mk.def.dispatch/python3,Python.demo

# Mapping the code to a different, more specific interpreter is also easy
demo.python39: mk.def.dispatch/python3.9,Python.demo
