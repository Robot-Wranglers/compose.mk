#!/usr/bin/env -S make -f
# demos/tui/dashboarding-dispatch-2.mk: 
#   Expanding the dashboarding-dispatch.mk TUI demo to show a refactored example.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
# USAGE: make -f demos/tui/dashboarding-widgets.mk demo.ui

include demos/tui/dashboarding-dispatch.mk
IMG_GOLANG_BASE?=docker.io/golang:1.24-bookworm
bottom: golang.dispatch/chain
chain: flux.and/clean,build,io.bash
golang.dispatch/%:
	${make} docker.image.dispatch/${IMG_GOLANG_BASE}/${*}
