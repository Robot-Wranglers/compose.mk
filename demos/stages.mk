#!/usr/bin/env -S make -f
#
# stages.mk:
#   Stacks & stages in plain Makefile, feature by feature.  A stage is a
#   named, file-backed JSON stack (`.stage.<name>`).  `enter`/`exit`
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
export CMK_STAGE_BANNER?=io.print.banner

stage.lifecycle:
	@# The full lifecycle: enter -> push -> read stack -> pop (LIFO) -> exit
	@# (cleanup).
	${stage.enter}/${@}
	${jb} step=build | ${stage.push}/${@}
	${jb} step=test  | ${stage.push}/${@}
	$(call log.io, ${@} ${sep} the whole stack, newest last:)
	${stage.stack}/${@} | ${jq} -c .[]
	popped=`${stage.pop}/${@} | ${jq} -c .` \
		&& $(call log.io, ${@} ${sep} popped the top ${sep} $${popped})
	${stage.exit}/${@}

stage.query:
	@# A stage is a lazy stack: skip `enter`, push straight in, then use the
	@# read-only primitives -- count and get (a jq projection).  `clean` at
	@# end.
	${jb} user=alice role=admin | ${stage.push}/${@}
	${jb} user=bob   role=user  | ${stage.push}/${@}
	${jb} user=carol role=admin | ${stage.push}/${@}
	n=`${stage.count}/${@}` \
		&& admins=`echo '[.[]|select(.role=="admin")|.user]' | ${stage.get}/${@}` \
		&& $(call log.io, ${@} ${sep} count=$${n} ${sep} admins=$${admins})
	${stage.clean}/${@}

stage.transform:
	@# update: rewrite the whole stack in place with a jq function (scale each
	@# .n by 10).
	${jb} n=1 | ${stage.push}/${@}
	${jb} n=2 | ${stage.push}/${@}
	${jb} n=3 | ${stage.push}/${@}
	echo 'map(.n | tonumber * 10)' | ${stage.update}/${@}
	scaled=`${stage.stack}/${@} | ${jq} -c .` \
		&& $(call log.io, ${@} ${sep} after update ${sep} $${scaled})
	${stage.clean}/${@}

__main__: stage.lifecycle stage.query stage.transform
