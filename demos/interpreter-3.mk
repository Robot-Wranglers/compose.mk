#!/usr/bin/env -S ./compose.mk mk.interpret
# Demonstrating compose.mk as an alternate interpreter for make.
# This is mostly used for inheriting signals/supervisors.  
#
# Main docs: https://robot-wranglers.github.io/compose.mk/signals/
#
# USAGE: 
#   ./demos/interpreter-3.mk

include compose.mk

python.img=python:3.11-slim-bookworm
python.interpreter=python

define python_script
from optparse import OptionParser
def main():
    parser = OptionParser(usage="usage: %prog [options] filename",version="%prog 1.0")
    parser.add_option("-f", "--foo", dest="foo", default='foo', help="set foo option")
    parser.add_option("-b", "--bar", 
        action="store_true", dest="bar", default=False, help="set bar option")
    (options, args) = parser.parse_args()
    if options.bar:
        print("bar is set")
    if options.foo:
        print(f"foo is {options.foo}")
    if len(args) > 0:
        print("Additional arguments:", args)
if __name__ == "__main__":
    print("hello python opt parse")
    main()
endef

# Target for running the script in a container, passing extra arguments in.
# This uses dense and idiomatic shorthand without explanation because 
# the container-dispatch is not the main point of this demo!
script.run:
	${mk.def.to.file}/python_script \
	&& cmd="python_script ${MAKE_CLI_EXTRA}" \
		${docker.image.run}/${python.img},${python.interpreter} \
	&& $(call mk.yield)

# Setting up a macro that uses ' -- ', we can abstract away the weird invocation
script=${make} script.run -- 

# Using the macro makes things tidy, and also completely abstracts the container.
__main__:; ${script} --foo my.foo --bar

my-normal-target:
	echo hello normal make target