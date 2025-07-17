#!/usr/bin/env -S make -f
# Demonstrating parsing positional arguments in parametric targets.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/parsing-parameters.mk

include compose.mk

__main__: \
	testing.comma_delimited/one,two,three \
	testing.slash_delimited/one/two/three

testing.slash_delimited/%:
	$(call bind.args.from_params, /) \
	&& printf "\n1st=$${_1st} 2nd=$${_2nd} 3rd=$${_3rd} 4th=$${_4th}\n" \
	&& printf "\nhead=$${_head} tail=$${_tail}\n"

testing.comma_delimited/%:
	$(call bind.args.from_params) \
	&& printf "\n1st=$${_1st} 2nd=$${_2nd} 3rd=$${_3rd} 4th=$${_4th}\n" \
	&& printf "\nhead=$${_head} tail=$${_tail}\n"