#!/usr/bin/env -S make -f
#
# cli-help.mk: CLI-help and supported syntax for docstrings.
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