# demos/dashboarding.mk: 
#   A very basic demo for getting started with custom TUIs.  See the main docs for discussion.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# USAGE: make -f demos/dashboarding.mk demo.ui


include compose.mk 

# Boilerplate & fake targets for classic clean/build/test
.DEFAULT_GOAL := all 
all: clean build test
clean:; echo cleaning 
build:; echo building 
test:; echo testing


# Full specification for a working TUI, using existing targets.
# The "top" pane will run the test target in a loop forever, and the
# "bottom" pane will run clean/build sequentially, then wait for user input.
top: flux.loopf/test
bottom: flux.and/clean,build
demo.ui: tux.open.horizontal/top,bottom