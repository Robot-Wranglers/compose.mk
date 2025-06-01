#!/usr/bin/env -S make -f
# demos/tui/user-input-2.mk: 
#   Demonstrates user-input with a file selector
# USAGE: ./demos/tui/user-input.mk

include compose.mk

__main__:
	header="Choose a moirai" \
	&& choices="clotho lachesis atropos" \
	&& ${io.get.choice} \
	&& echo "chosen=$${chosen}"