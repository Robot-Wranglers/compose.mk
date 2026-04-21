#!/usr/bin/env -S make -f
#
# stages.mk:
#   Stacks & stages in plain Makefile, feature by feature.  A stage is a
#   named, file-backed JSON stack (`.flux.stage.<name>`).  `enter`/`exit`
#   add a banner, an entry-record, and auto-cleanup; underneath it is just
#   a lazy stack, so it also gets the stack primitives -- count, get (a jq
#   query), and update (a jq transform in place).  `${@}` is the current
#   target name, used here as the stage name.
#
#   See the docs: https://robot-wranglers.github.io/compose.mk/stages
#
# USAGE: ./demos/stages.mk

include compose.mk

# Draw banners with the plain built-in instead of the (dockerized) gum
# default.
export FLUX_STAGE_BANNER?=io.print.banner

stage.lifecycle:
	@# The full lifecycle: enter -> push -> read stack -> pop (LIFO) -> exit
	@# (cleanup).
	${flux.stage.enter}/${@}
	${jb} step=build | ${flux.stage.push}/${@}
	${jb} step=test  | ${flux.stage.push}/${@}
	$(call log.io, ${@} ${sep} the whole stack, newest last:)
	${flux.stage.stack}/${@} | ${jq} -c .[]
	popped=`${flux.stage.pop}/${@} | ${jq} -c .` \
		&& $(call log.io, ${@} ${sep} popped the top ${sep} $${popped})
	${flux.stage.exit}/${@}

stage.query:
	@# A stage is a lazy stack: skip `enter`, push straight in, then use the
	@# read-only primitives -- count and get (a jq projection).  `clean` at
	@# end.
	${jb} user=alice role=admin | ${flux.stage.push}/${@}
	${jb} user=bob   role=user  | ${flux.stage.push}/${@}
	${jb} user=carol role=admin | ${flux.stage.push}/${@}
	n=`${flux.stage.count}/${@}` \
		&& admins=`echo '[.[]|select(.role=="admin")|.user]' | ${flux.stage.get}/${@}` \
		&& $(call log.io, ${@} ${sep} count=$${n} ${sep} admins=$${admins})
	${flux.stage.clean}/${@}

stage.transform:
	@# update: rewrite the whole stack in place with a jq function (scale each
	@# .n by 10).
	${jb} n=1 | ${flux.stage.push}/${@}
	${jb} n=2 | ${flux.stage.push}/${@}
	${jb} n=3 | ${flux.stage.push}/${@}
	echo 'map(.n | tonumber * 10)' | ${flux.stage.update}/${@}
	scaled=`${flux.stage.stack}/${@} | ${jq} -c .` \
		&& $(call log.io, ${@} ${sep} after update ${sep} $${scaled})
	${flux.stage.clean}/${@}

__main__: stage.lifecycle stage.query stage.transform
