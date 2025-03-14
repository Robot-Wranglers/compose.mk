#!/usr/bin/env -S make -f
# demos/itest.mk: 
#   Integration test-suite.  
#   This isn't pretty or instructive like the other demos, 
#   might contain WIP, and the main point is just increasing test coverage.
#
#  This is integration'y because it actually uses external compose files
#  and exercises the bridge / automation scaffolding generation.
#
#   USAGE: ./demos/itest.mk

# Include compose.mk so we can use `compose.import` macro, and
# otherwise exercise base-targets that are provided by the lib
include compose.mk

.DEFAULT_GOAL := all 

# Load all services from 1 compose file, *not* into the root namespace.
# $(eval $(call compose.import.as, ▰, demos/data/docker-compose.cm-tools.yml))

# Load all services from 2 compose files into 1 namespace.
$(eval $(call compose.import, demos/data/docker-compose.yml, ▰))

all: flux.star/test.* 

test.mk.reflection:
	$(call log.test_case, testing reflection)
	./compose.mk \
		mk.set/foo/bar mk.get/foo \
		mk.ifdef/foo mk.ifndef/baz

test.flux.if.then:
	$(call log.test_case, test a few kinds of if/then flows)
	set -x \
	&& ./compose.mk flux.if.then/flux.ok,flux.ok \
	&& ./compose.mk flux.if.then/flux.fail,flux.ok 

test.flux.do.when:
	$(call log.test_case, test a few kinds of do/when flows)
	set -x \
	&& ./compose.mk flux.do.when/flux.ok,flux.ok \
	&&	./compose.mk flux.negate/flux.do.when/flux.fail,flux.ok

test.signals:
	$(call log.test_case, mk.interrupt should throw an error)
	! ./compose.mk mk.interrupt
	$(call log.test_case, signal handler should not be installed for library usage)
	! make mk.parse.local|grep mk.interrupt
	
demo: ▰/debian/self.demo
	@# New target declaration that we can use to run stuff
	@# inside the `debian` container.  The syntax conventions
	@# are configured by the `compose.import` call we used above.

test.ticker:
	@# FIXME: timeout kills the whole process?
	@# text=" testing ticker " make flux.timeout/2/tux.widget.ticker || true

# Displays platform info to show where target is running.
# Since this target is intended to be private, we will 
# prefix "self" to indicate it should not run on host.
self.demo:
	. /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
demo.double.dispatch: ▰/debian/self.demo ▰/alpine/self.demo

# test.containerized.tty.output: 
# 	cmd='sleep 2' label='testing gum spinner inside container' make io.gum.spin

test.import.root:
# make io.print.div label="${bold_cyan}${@}${no_ansi}"
# $(call log, ${dim_cyan}Test import-to-root argument for compose.import)
# # test that the 4th argument for
# # import-to-root-namespace is honored
# ! echo uname | make debian.pipe 2>/dev/null
# echo uname | make docker-compose.cm-tools/debian.pipe 2>/dev/null
# echo uname | make docker-compose/alpine.shell.pipe

test.main.bridge:
	$(call log.test_case, main bridge)
	make io.print.div label="${cyan}${@}${no_ansi}"
	$(call log.test_case, Test service enumeration\nTarget @ <compose_file>.services)
	${make} docker-compose.services
	$(call log.test_case, Test detection\nTarget @ <compose_file>.get_shell)
	${make} docker-compose/alpine.get_shell

# test.multiple.compose.files:
# 	make io.print.div label="${cyan}${@}${no_ansi}"
# 	$(call log, ${dim_cyan}Test services enumeration, 2nd file\nTarget @ <compose_file>/<svc>.services)
# 	${make} docker-compose.services
# 	$(call log, ${dim_cyan}Test Streaming commands, 2nd file\nTarget @ <compose_file>/<svc>.pipe)
# 	echo uname -n -v | ${make} docker-compose/debian.pipe \

# test.compose.pipes:
# 	make io.print.div label="${cyan}${@}${no_ansi}"
# 	$(call log, ${dim_cyan}Streaming commands to container\nTarget @ <svc>.shell.pipe)
# 	echo uname -n -v | ${make} docker-compose/alpine.shell.pipe
# 	$(call log, ${dim_cyan}Test streaming commands to container\nTarget @ <compose_file_stem><svc>.shell.pipe)
# 	echo uname -n -v | ${make} docker-compose/alpine.shell.pipe
# 	$(call log, ${dim_cyan}Test streaming data to container\nTarget @ <svc>.shell.pipe ${no_color})
# 	echo 'foo: bar' | ${make} docker-compose.cm-tools/yq.pipe
# 	set -x && echo '{"foo":"bar"}' | cmd='.foo' make docker-compose.cm-tools/jq.pipe

# test.compose.services:
# 	make io.print.div label="${cyan}${@}${no_ansi}"
# 	$(call log, ${dim_cyan}Test main entrypoints Target @ <compose_file>/<svc> ${no_color})
# 	${make} docker-compose.cm-tools/yq cmd='--version'
# 	${make} docker-compose.cm-tools/jq cmd='--version'

test.dispatch.retvals:
	$(call log.test_case, Checking dispatch return codes)
	! (echo exit 1 | ${make} docker-compose/debian.shell.pipe 2>/dev/null)
	echo exit  | ${make} docker-compose/debian.shell.pipe

# test.dispatch:
# 	make io.print.div label="${cyan}${@}${no_ansi}"
# 	$(call log, ${dim_cyan}Dispatch using private base target:${no_color})
# 	echo uname | pipe=yes ${make} ▰/debian
# 	$(call log, ${dim_cyan}Dispatch using debian container:${no_color})
# 	${make} ▰/debian/self.container.dispatch
# 	$(call log, ${dim_cyan}Dispatch using alpine container:${no_color})
# 	${make} ▰/alpine/self.container.dispatch
# self.container.dispatch:
# 	printf "in container `hostname`, platform info: `uname`\n"

# test.flux.lib: test.flux.finally test.flux.try.except.finally test.flux.mux test.flux.pipe.fork test.flux.loop

test.flux.try.except.finally:
	$(call log.test_case, Checking)
	make flux.try.except.finally/flux.fail,flux.ok,flux.ok
	! make flux.try.except.finally/flux.ok,flux.ok,flux.fail
	# except fails, but try succeeds so it never runs
	make flux.try.except.finally/flux.ok,flux.fail,flux.ok
	! make flux.try.except.finally/flux.fail,flux.fail,flux.ok
	make flux.try.except.finally/flux.ok,flux.ok,flux.ok

test.flux.finally:
	$(call log.test_case, Checking)
	# demo of using finally/always functionality in a pipeline.  touches a tmpfile 
	# somewhere in the middle of a failing pipeline without getting to the cleanup 
	# task, and it should be cleaned up anyway.
	bash -i -c "(make \
		flux.finally/.file.cleanup \
		.file.touch flux.fail file-cleanup || true)"
	# NB: cannot assert this from here because cleanup only runs when the *test process* exits
	# ! ls .tmp.test.flux.finally	
.file.touch:
	touch .tmp.test.flux.finally

.file.cleanup:
	rm .tmp.test.flux.finally

# test.flux.loop:
# 	${make} docker-compose.dispatch/alpine/flux.loop/2/io.time.wait

# test.flux.pipe.fork:
# 	echo {} | ${make} flux.pipe.fork/docker-compose.cm-tools/yq,docker-compose.cm-tools/jq
# 	echo {} | ${make} flux.split/docker-compose.cm-tools/yq,docker-compose.cm-tools/jq

test.flux.retry:
	$(call log.test_case, Checking)
	! interval=1 make flux.retry/3/flux.fail

test.flux.apply:
	$(call log.test_case, Checking)
	${make} flux.apply/flux.echo,THUNK ${stream.obliviate}

test.flux.starmap:
	$(call log.test_case, Checking)
	${make} ./compose.mk flux.starmap/flux.echo,flux.echo/bonk ${stream.obliviate}

test.flux.apply.later:
	$(call log.test_case, Checking)
	${make} flux.apply.later/2/io.time.wait/1 ${stream.obliviate}

test.flux.mux:
	$(call log.test_case, Checking)
	make flux.mux targets="io.time.wait,io.time.wait,io.time.wait/2" | jq .
	make flux.join targets="io.time.wait,io.time.wait,io.time.wait/2" | jq .
	make flux.mux/io.time.wait

test.docker.run:
	$(call log.test_case, Checking)
	img=debian/buildd:bookworm ./compose.mk docker.dispatch/flux.ok
	echo hello-python-docker1 | ${make} .test.docker.run.def
	echo hello-python-docker2 | entrypoint=cat cmd=/dev/stdin img=python:3.11-slim-bookworm make docker.run.sh
	entrypoint=python cmd='--version' img=python:3.11-slim-bookworm make docker.run.sh
	echo {} | cmd=. img=ghcr.io/jqlang/jq:1.7.1 make docker.start
.test.docker.run.def:
	entrypoint=python def=script.demo.docker.run.def \
	img=python:3.11-slim-bookworm make docker.run.def
define script.demo.docker.run.def 
# python script 
import sys
print(['input',sys.stdin.read().strip()])
endef
