#!/usr/bin/env -S make -f
# demos/stages-idiom.mk: 
#
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
#   USAGE: ./demos/stages-idiom.mk

include compose.mk
.DEFAULT_GOAL := validate

# Wrap targets with entry/exit as an explicit context-manager
validate: \
	flux.stage.enter/VALIDATION \
		project.scan \
		project.analyze \
	flux.stage.exit/VALIDATION

project.scan:
	echo '["results"]' | ./compose.mk flux.stage.push/VALIDATION

project.analyze:
	echo '["other results"]' | ./compose.mk flux.stage.push/VALIDATION