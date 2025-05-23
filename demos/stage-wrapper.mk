#!/usr/bin/env -S make -f
# demos/stage-wrapper.mk: 
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
#   USAGE: ./demos/stages.mk

include compose.mk

project.scan:
	echo '["results"]' | ./compose.mk flux.stage.push/VALIDATION

project.analyze:
	echo '["other results"]' | ./compose.mk flux.stage.push/VALIDATION

# Override the default target used to print the entry-banner
export banner_target?=io.figlet

__main__: flux.stage.wrap/INIT/project.scan,project.analyze
