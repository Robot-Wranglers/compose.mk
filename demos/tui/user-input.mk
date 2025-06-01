#!/usr/bin/env -S make -f
# demos/tui/user-input.mk: 
#   Demonstrates user-input with a file selector
# USAGE: ./demos/tui/user-input.mk

include compose.mk 

__main__:
	pattern='*.mk' dir=demos \
		${make} flux.select.file/mk.select