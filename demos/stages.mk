# demos/stages.mk: 
#   Demonstrating stages, stacks, and artifact-related features of compose.mk
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/stages.mk

include compose.mk
.DEFAULT_GOAL := demo.stage

demo.stage: flux.star/test.stage.*

test.stage.basic:
	$(call log.target, declare a stage with the same name as the current target & get stage name back)
	./compose.mk flux.stage/${@} flux.stage
	
test.stage.push:
	$(call log.target, push json data onto this stages stack)
	${jb} foo=bar | ./compose.mk flux.stage.push/${@} 
	$(call log.target, pop it off again, unpacking it to confirm json.)
	./compose.mk flux.stage.pop/${@} | ${stream.peek} | ${jq} -e -r .foo
	$(call log.target, popping an empty stack is allowed)
	./compose.mk flux.stage.pop/${@}

test.stage.cleaning:
	$(call log.target, confirm that declaring a stage and pushing no data does NOT create a stack file & that cleaning removes it)
	./compose.mk flux.stage/test && ! ls .flux.stage.test 2>/dev/null 
	${jb} foo=bar | ./compose.mk flux.stage.push/test && ls .flux.stage.test && ./compose.mk flux.stage.clean; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)