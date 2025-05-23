#!/usr/bin/env -S make -f
# demos/exotic-targets.mk: 
#   Demos make-targets in foreign languages and shows them working with pipes.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   USAGE: ./demos/exotic-targets.mk

include compose.mk

# A more complex python script, testing comments, indention, & using pipes
define python_script
# python script
import sys, json
input = json.loads(sys.stdin.read())
input.update(hello_python=sys.platform)
output = input
print(json.dumps(output))
for x in [1, 2, 3]:
  msg=f"{x} testing loops, indents, string interpolation"
  print(msg, file=sys.stderr)
endef

# Runs the script, passing data into the pipe
__main__:
	echo '{"hello":"bash"}' \
	| ${make} mk.def.dispatch/python3,python_script
