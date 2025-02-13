# demos/stages.mk: 
#   Mad-science demo. See the docs for discussion
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/stages.mk

.DEFAULT_GOAL := test.stage

include compose.mk

test.stage:
	# declare a stage
	./compose.mk flux.stage/${@}
	${jb.run} foo=bar | ./compose.mk flux.stage.push/${@} 
	./compose.mk flux.stage.pop/${@}
	./compose.mk flux.stage/test flux.stage.clean; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)
	echo 33 | ./compose.mk flux.stage/test flux.stage.push; (ls .flux.stage.test 2>/dev/null && exit 1 || exit 0)