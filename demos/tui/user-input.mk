#!/usr/bin/env -S make -f
# demos/tui/user-input.mk: 
#   Demonstrates user-input with a file selector
#   USAGE: make -f demos/tui/user-input.mk
include compose.mk 
.DEFAULT_GOAL := demo

demo:
	pattern='*.mk' dir=demos \
		${make} flux.select.file/mk.select