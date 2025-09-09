#!/usr/bin/env -S make -f
# Demonstrates user-input with a file selector
# USAGE: ./demos/tui/user-input.mk

include compose.mk 

__main__:
	pattern='*.mk' dir=demos \
		${make} flux.select.file/mk.select