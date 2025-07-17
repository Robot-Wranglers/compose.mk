#!/usr/bin/env -S make -f
# Demos make-targets in foreign languages, without a container.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/local-interpreter.mk

include compose.mk

# Look, here's a simple python script 
define script.py
import sys
print('python world')
print('dollar signs are safe: $')
endef

# Minimal boilerplate to run the script, using a specific interpreter (python3).
# No container here, so this requires that the interpreter is actually available.
__main__: polyglot.dispatch/python3,script.py

# Multiple mappings for script/interprreter can co-exist,
# and using a more specific interpreter is just mentioning it.
demo.python39: polyglot.dispatch/python3.9,script.py
