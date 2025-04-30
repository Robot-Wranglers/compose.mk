#!/usr/bin/env -S ./compose.mk mk.interpret
# demos/cli-help-shebang.mk: 
#   Demonstrates compose.mk usage as an interpreter, 
#   which amongst other things enables full support for online help.
#
# See the docs: https://robot-wranglers.github.io/compose.mk/cli-help/  
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE:  
#   ./demos/cli-help-shebang.mk help my-target
#   ./demos/cli-help-shebang.mk help my-parametric-target

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