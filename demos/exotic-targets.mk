# demos/exotic-targets.mk: 
#   Demos make-targets in foreign languages and shows them working with pipes.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/exotic-targets.mk

include compose.mk
.DEFAULT_GOAL := demo.python.pipes


# A more complex python script, testing comments, indention, & using pipes
define python.script
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
demo.python.pipes:
	echo '{"hello":"bash"}' \
	| ${make} mk.def.dispatch/python3/python.script
