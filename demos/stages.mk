#!/usr/bin/env -S make -f
# stages.mk:
#   A worked example of stages & stacks in compose.mk -- naming a stage, pushing
#   and reading JSON, popping a value back off, and cleaning up on exit.  A stage is
#   just a file-backed JSON stack (`.flux.stage.<name>`), handy for passing structured
#   values between targets or across the steps of a pipeline.
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/stages
#
# USAGE: ./demos/stages.mk

include compose.mk

# Draw banners with the plain built-in instead of the (dockerized) gum default.
export banner_target?=io.print.banner

__main__: demo.stage

# `${@}` is shorthand for "the current target name".  Using it as the stage name is a
# tidy convention -- a family of targets that share a name-prefix then share one stack.
demo.stage:
	$(call log.io, ${@} ${sep} a fresh stage can report its own name)
	${flux.stage.enter}/${@} flux.stage

	$(call log.io, ${@} ${sep} push two JSON objects onto the stage stack)
	${jb} one=1 | ${flux.stage.push}/${@}
	${jb} two=2 | ${flux.stage.push}/${@}

	$(call log.io, ${@} ${sep} read the whole stack back as JSON)
	${flux.stage.stack}/${@} | ${jq} .

	$(call log.io, ${@} ${sep} pop the top value off (LIFO) and pull a field from it)
	${flux.stage.pop}/${@} | ${jq} -r .two

	$(call log.io, ${@} ${sep} exit the stage to clean up its stack file)
	${flux.stage.exit}/${@}
