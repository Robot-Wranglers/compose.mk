#!/usr/bin/env -S make -f
#
# stage-wrapper.mk:
#   Stages, stacks, and artifact-related features of compose.mk
#
#   See the docs for more discussion:
#   https://robot-wranglers.github.io/compose.mk/stages
#
# USAGE: ./demos/stage-wrapper.mk

include compose.mk

# Override the default target used to print the entry-banner
export CMK_STAGE_BANNER?=io.figlet

__main__: stage.wrap/VALIDATION/project.scan,project.analyze

project.scan:
	echo '["results"]' | ${stage.push}/VALIDATION

project.analyze:
	echo '["other results"]' | ${stage.push}/VALIDATION

