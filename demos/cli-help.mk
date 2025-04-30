#!/usr/bin/env -S make -f
# demos/cli-help.mk: 
#   Demonstrates CLI-help and supported syntax for docstrings.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE:  ./demos/cli-help.mk

include compose.mk 

__main__: my-target my-parametric-target/FOO

my-target:
	@# Comment line one
	@# **Markdown is supported.**
	echo your implementation here

my-parametric-target/%:
	@# Comment line one
	@# **Markdown is supported.**
	echo your implementation here