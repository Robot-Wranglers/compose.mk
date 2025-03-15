#!/usr/bin/env -S ./compose.mk mk.interpret
# demos/cli-help-shebang.mk: 
#   Demonstrates compose.mk usage as a wrapper, which amongst other things enables full support for online help.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
# USAGE:  demos/cli-help-shebang.mk

include compose.mk 
.DEFAULT_GOAL=__main__

__main__:

my-target:
	@# Comment line one
	@# **Markdown is supported.**
	echo your implementation here

my-parametric-target/%:
	@# Comment line one
	@# **Markdown is supported.**
	echo your implementation here