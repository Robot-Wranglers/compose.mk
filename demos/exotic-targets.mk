#!/usr/bin/env -S make -f
# Demos make-targets in foreign languages and shows them working with pipes.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/exotic-targets.mk

include compose.mk

# A more complex python script, testing comments, indention, & using pipes
define script.py
import sys, json
input = json.loads(sys.stdin.read())
input.update(hello_python=sys.platform)
output = input
print(json.dumps(output))
for x in [1, 2, 3]:
  msg=f"{x} testing loops, indents, string interpolation"
  print(msg, file=sys.stderr)
endef

# Generates JSON with `jb`, passes data with a pipe, 
# then parses JSON again on the python side.
__main__:
	${jb} hello=bash \
		| ${make} polyglot.dispatch/python3,script.py
