#!/usr/bin/env -S make -f
# demos/tui/dashboarding-dispatch-2.mk: 
#   Expanding the dashboarding-dispatch.mk TUI demo to show a refactored example.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE: ./demos/tui/dashboarding-widgets.mk demo.ui

include demos/tui/dashboarding-dispatch.mk
golang.base?=docker.io/golang:1.24-bookworm
bottom: golang.dispatch/chain
chain: flux.and/clean,build,io.shell
golang.dispatch/%:
	${docker.image.dispatch}/${golang.base}/${*}
