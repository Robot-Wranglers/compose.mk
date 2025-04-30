#!/usr/bin/env -S make -f
# demos/tui/dashboarding-wdgets.mk: 
#   Expanding thedashboarding.mk TUI demo to include containers-as-widgets.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE: ./demos/tui/dashboarding-widgets.mk demo.ui

include compose.mk 

# Boilerplate & fake targets for classic clean/build/test
.DEFAULT_GOAL := all 
all: clean build test
clean:; echo cleaning 
build:; echo building 
test:; echo testing


# Full specification for a working TUI, using existing targets.
# The "top" pane will run the test target in a loop forever
# The "bottom" pane will run clean/build sequentially, then wait.
# The "middle" pane starts the "dry" container, i.e. a dockerized 
# version of a docker system-monitor. See https://github.com/moncho/dry
top: flux.loopf/test
middle: docker.start.tty/moncho/dry
bottom: flux.and/clean,build
demo.ui: tux.open.horizontal/top,middle,bottom
