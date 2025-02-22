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
	
	$(call log.target, show whole stack)
	${jb} one=1 | ./compose.mk flux.stage.push/${@} 
	${jb} two=2 | ./compose.mk flux.stage.push/${@} 
	./compose.mk flux.stage.stack/${@} | jq .
	
	$(call log.target, push json data onto this stages stack)
	${jb} foo=bar | ./compose.mk flux.stage.push/${@} stage.pop/${@} | ${stream.peek} | ${jq} -e -r .foo
	$(call log.target, popping an empty stack is also allowed)
	./compose.mk flux.stage.pop/${@}

	$(call log.target, confirm that declaring a stage and pushing no data does NOT create a stack file & that cleaning removes it)
	./compose.mk flux.stage/test && ! ls .flux.stage.test 2>/dev/null 
	${jb} foo=bar | ./compose.mk flux.stage.push/test && ls .flux.stage.test && ./compose.mk flux.stage.clean; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)