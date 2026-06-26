#!/usr/bin/env -S make -f
# stage-wrapper.mk:
#   Stages, stacks, and artifact-related features of compose.mk
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
# USAGE: ./demos/stages.mk

include compose.mk

# Override the default target used to print the entry-banner
export banner_target?=io.figlet

__main__: flux.stage.wrap/INIT/project.scan,project.analyze

project.scan:
	echo '["results"]' | ${flux.stage.push}/VALIDATION

project.analyze:
	echo '["other results"]' | ${flux.stage.push}/VALIDATION

