#!/usr/bin/env -S make -f
#
# parsing-parameters.mk:
#   Parsing positional arguments in parametric targets.
#
# USAGE: ./demos/parsing-parameters.mk

include compose.mk

__main__: \
	testing.comma_delimited/one,two,three \
	testing.slash_delimited/one/two/three

testing.slash_delimited/%:
	$(call bind.posargs, /) \
	&& printf "\n1st=$${_1st} 2nd=$${_2nd} 3rd=$${_3rd} 4th=$${_4th}\n" \
	&& printf "\nhead=$${_head} tail=$${_tail}\n"

testing.comma_delimited/%:
	$(call bind.posargs) \
	&& printf "\n1st=$${_1st} 2nd=$${_2nd} 3rd=$${_3rd} 4th=$${_4th}\n" \
	&& printf "\nhead=$${_head} tail=$${_tail}\n"