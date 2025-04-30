#!/usr/bin/env -S make -f
# demos/tui/dashboarding-dispatch.mk: 
#   Expanding the dashboarding.mk TUI demo to include container dispatch.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/tui/dashboarding-widgets.mk demo.ui

include compose.mk 

golang.base=golang\:1.24-bookworm

__main__: clean build test

# Fake targets for classic clean/build/test
clean:; which gofmt; echo cleaning 
build:; which go; go version
test:; echo testing

# Full specification for a working TUI, using existing targets.
# The "top" pane will run the test target in a loop forever
# The "bottom" pane will run clean/build sequentially, then wait.
top: flux.loopf/test
bottom: docker.image.dispatch/${golang.base}/flux.and/clean,build,io.bash
demo.ui: tux.open.horizontal/top,bottom