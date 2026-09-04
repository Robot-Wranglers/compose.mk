#!/usr/bin/env -S make -f
#
# local-interpreter.mk:
#   The plain-Makefile twin of demos/cmk/local-interpreter.cmk: run a
#   foreign-language program on the host's own python, no container.  Here
#   the mechanism is explicit (a script lives in a define block, dispatched
#   onto a named host interpreter) where the .cmk hides it behind the
#   (| body |) in host.native.python; there is no container, so the
#   interpreter must actually be present on the host.
#
# USAGE: ./demos/local-interpreter.mk

include compose.mk

# hello: two lines of python on the host interpreter.  A make define keeps
# its body verbatim, so the dollar survives, same as a raw .cmk banana.
define hello.py
print('python world')
print('dollars are safe: $')
endef

# version: the same idiom, reporting the host python it landed on.
define version.py
import sys
print('running on', sys.version.split()[0])
endef

__main__: hello version
hello: host.dispatch/python3,hello.py
version: host.dispatch/python3,version.py
