# demos/dashboarding-dispatch.mk: 
#   Expanding the dashboarding.mk TUI demo to include container dispatch.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# USAGE: make -f demos/dashboarding-widgets.mk demo.ui


include compose.mk 

# Boilerplate & fake targets for classic clean/build/test
.DEFAULT_GOAL := all 
all: clean build test
clean:; which gofmt; echo cleaning 
build:; which go; go version
test:; echo testing

# Full specification for a working TUI, using existing targets.
# The "top" pane will run the test target in a loop forever
# The "bottom" pane will run clean/build sequentially, then wait.
top: flux.loopf/test
bottom: docker.image.dispatch/golang\:1.24-bookworm/flux.apply/clean,build,io.bash
demo.ui: tux.open.horizontal/top,bottom