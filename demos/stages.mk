#!/usr/bin/env -S make -f
# demos/stages.mk: 
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
# USAGE: ./demos/stages.mk

include compose.mk

# disable gum usage by overriding the default target for printing banners
export banner_target?=io.print.banner

__main__: flux.star/test.stage

test.stage.basic:
	@# Note that ${@} is shorthand for "current target name"-- 
	@# we use that for the stage name everywhere
	$(call log.test, declare a stage & get stage name back)
	./compose.mk flux.stage/${@} flux.stage 

	$(call log.test, stage stack should exist still with legal JSON if not explicitly exited)
	ls .flux.stage.${@} && cat .flux.stage.${@} | ${jq} -e .
	
	$(call log.test, exiting the stage removes the stack file)
	${make} flux.stage.exit/${@}
	! ls .flux.stage.${@} 2>/dev/null
	
	$(call log.test, using a stage by pushing data causes stack to exist)
	${jb} one=1 | ./compose.mk flux.stage.push/${@} 
	ls .flux.stage.${@} 2>/dev/null
	${jb} two=2 | ./compose.mk flux.stage.push/${@} 
	
	$(call log.test, getting the whole stack is possible and returns JSON)
	./compose.mk flux.stage.stack/${@} | ${jq} -e .
	${make} flux.stage.exit/${@}
	
	$(call log.test, testing popping JSON data off the stack)
	${jb} foo=bar | ./compose.mk flux.stage.push/${@} 
	./compose.mk flux.stage.stack/${@} | ${jq} .
	./compose.mk flux.stage.pop/${@} | ${stream.peek} | ${jq} -e -r .foo
	
	${make} flux.stage.exit/${@}

test.stage.empty:
	$(call log.test, popping an empty stack is also allowed)
	./compose.mk flux.stage.pop/${@}
	./compose.mk flux.stage.pop/${@}
	./compose.mk flux.stage.pop/${@}
	./compose.mk flux.stage.pop/${@}
	${make} flux.stage.exit/${@}
	./compose.mk flux.stage.pop/${@}