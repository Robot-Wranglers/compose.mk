#!/usr/bin/env -S make -f
# stages-idiom.mk:
#
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
# USAGE: ./demos/stages-idiom.mk

include compose.mk

__main__: validate

# Wrap targets with entry/exit as an explicit context-manager
validate: \
	flux.stage.enter/VALIDATION \
		project.scan \
		project.analyze \
	flux.stage.exit/VALIDATION

project.scan:
	echo '["results"]' | ${flux.stage.push}/VALIDATION

project.analyze:
	echo '["other results"]' | ${flux.stage.push}/VALIDATION