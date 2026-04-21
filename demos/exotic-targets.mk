#!/usr/bin/env -S make -f
#
# exotic-targets.mk:
#   Make-targets in foreign languages and shows them working with pipes.
#
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

__main__:
	@# Generates JSON with `jb`, passes data with a pipe, 
	@# then parses JSON again on the python side.
	${jb} hello=bash \
		| ${make} host.dispatch/python3,script.py
