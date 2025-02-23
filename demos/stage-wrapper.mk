# demos/stage-wrapper.mk: 
#
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
#   USAGE: make -f demos/stages.mk

include compose.mk
.DEFAULT_GOAL := demo.stage.wrapper

demo.stage.wrapper: flux.stage.wrap/MY_STAGE/phase1,phase2,phase3

phase1:; echo phase1
phase2:; echo phase2
phase3:; echo phase3