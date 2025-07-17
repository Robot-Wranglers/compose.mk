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

# Load all services from 1 compose file, *not* into the root namespace.
# $(call compose.import.as, file=demos/data/docker-compose.cm-tools.yml namespace=▰)

# Load all services from 2 compose files into 1 namespace.
$(call compose.import, file=demos/data/docker-compose.yml namespace=▰)

__main__: flux.star/test.*
	
test.mk.assert_env_var:
	$(call log.test, Testing assert.env_var macros)
	my_var=1; $(call mk.assert.env, my_var)
	$(call log.test, assert.env_var fails if env not set)
	! $(call mk.assert.env, my_var) ${stderr_devnull}
	$(call log.test, assert works for multiple vars)
	another_var=2; my_var=1; $(call mk.assert.env, my_var another_var)
	$(call log.test, assert fails for multiple vars when one is not set)
	! ( another_var=2; my_var=1; $(call mk.assert.env, my_var another_var missing) ) ${stderr_devnull}
	$(call log.test, assert.env works as target for multiple vars when one is not set)
	foo=1 bar=2 ./compose.mk mk.assert.env/foo,bar
	! bar=2 ./compose.mk mk.assert.env/foo,bar ${stderr_devnull}

test.compose.validate:
	$(call log.test, Testing compose-file validation)
	./compose.mk compose.validate/demos/data/docker-compose.yml
	$(call log.test, Validation for bad file should fail)
	! ./compose.mk compose.validate/demos/data/doesnt-exist

test.compose.services:
	$(call log.test, Listing compose-services)
	./compose.mk compose.services/demos/data/docker-compose.yml | grep alpine
	$(call log.test, Listing services fails for bad file)
	! ./compose.mk compose.services/demos/data/doesnt-exist

test.mk.reflection:
	$(call log.test, Testing reflection)
	./compose.mk \
		mk.set/foo/bar mk.get/foo \
		mk.ifdef/foo mk.ifndef/baz

test.flux.if.then:
	$(call log.test, Test a few kinds of if/then flows)
	set -x \
	&& ./compose.mk flux.if.then/flux.ok,flux.ok \
	&& ./compose.mk flux.if.then/flux.fail,flux.ok 

test.flux.do.when:
	$(call log.test, Test a few kinds of do/when flows)
	set -x \
	&& ./compose.mk flux.do.when/flux.ok,flux.ok \
	&&	./compose.mk flux.negate/flux.do.when/flux.fail,flux.ok

test.signals:
	$(call log.test, mk.interrupt should throw an error)
	! ./compose.mk mk.interrupt
	$(call log.test, Signal handler should not be installed for library usage)
	! ${make} mk.parse.local | grep mk.interrupt
	
demo: ▰/debian/self.demo
	@# New target declaration that we can use to run stuff
	@# inside the `debian` container.  The syntax conventions
	@# are configured by the `compose.import` call we used above.

test.ticker:
	@# FIXME: timeout kills the whole process?
	@# text=" testing ticker " ${make} flux.timeout/2/tux.widget.ticker || true

# Displays platform info to show where target is running.
# Since this target is intended to be private, we will 
# prefix "self" to indicate it should not run on host.
self.demo:
	. /etc/os-release && printf "$${PRETTY_NAME}\n"
	uname -n -v
demo.double.dispatch: ▰/debian/self.demo ▰/alpine/self.demo

# test.containerized.tty.output: 
# 	cmd='sleep 2' label='testing gum spinner inside container' ${make} io.gum.spin

# test.compiler:
# 	$(call log.test, Compilation of CMK gives legal makefile + library fxns)
# 	${io.mktemp} \
# 	&& cat demos/cmk/structured-io.cmk | ./compose.mk mk.compile > $${tmpf} \
# 	&& chmod +x $${tmpf} \
# 	&& $${tmpf} flux.ok
# 	$(call log.test, Compilation of makefile gives legal makefile + library fxns)
# 	${io.mktemp} \
# 	&& cat demos/no-include.mk | ./compose.mk mk.compile > $${tmpf} \
# 	&& chmod +x $${tmpf} \
# 	&& $${tmpf} clean flux.ok

test.main.bridge:
	$(call log.test, main bridge)
	${make} io.print.banner label="${cyan}${@}${no_ansi}"
	$(call log.test, Test service enumeration\nTarget @ <compose_file>.services)
	${make} docker-compose.services
	$(call log.test, Test pulling configuration data)
	${make} docker-compose/alpine.get_config
	${make} docker-compose/alpine.get_config/build.context

test.get_shell:
	@# FIXME: broken from github-actions, 'input device is not a tty'
	$(call log.test, Test detection\nTarget @ <compose_file>.get_shell)
	#${make} docker-compose/alpine.get_shell

test.dispatch.retvals:
	$(call log.test, Checking dispatch return codes)
	! (echo exit 1 | ${make} docker-compose/debian.shell.pipe 2>/dev/null)
	echo exit  | ${make} docker-compose/debian.shell.pipe

test.flux.map:
	$(call log.test, Checking flux.map dispatches for each input)
	./compose.mk flux.map/flux.echo,foo,bar | grep foo
	./compose.mk flux.map/flux.echo,foo,bar | grep bar

test.flux.try.except.finally:
	$(call log.test, testing try.except.finally)
	./compose.mk flux.try.except.finally/flux.fail,flux.ok,flux.ok
	! ./compose.mk flux.try.except.finally/flux.ok,flux.ok,flux.fail
	# except fails, but try succeeds so it never runs
	./compose.mk flux.try.except.finally/flux.ok,flux.fail,flux.ok
	! ./compose.mk flux.try.except.finally/flux.fail,flux.fail,flux.ok
	./compose.mk flux.try.except.finally/flux.ok,flux.ok,flux.ok

test.flux.context_manager:
	$(call log.test, testing ${@} calls enter)
	${make} flux.context_manager/flux.ok,my_ctx_man | grep my_ctx_man.enter
	${make} flux.context_manager/flux.ok,my_ctx_man | grep my_ctx_man.exit
my_ctx_man.enter:; printf "${@}"
my_ctx_man.exit:; printf "${@}"

test.flux.finally:
	$(call log.test, testing flux.finally)
	# demo of using finally/always functionality in a pipeline.  touches a tmpfile 
	# somewhere in the middle of a failing pipeline without getting to the cleanup 
	# task, and it should be cleaned up anyway.
	bash -i -c "(${make} \
		flux.finally/.file.cleanup \
		.file.touch flux.fail file-cleanup || true)"
	# NB: cannot assert this from here because cleanup only runs when the *test process* exits
	# ! ls .tmp.test.flux.finally	
.file.touch:
	touch .tmp.test.flux.finally

.file.cleanup:
	rm .tmp.test.flux.finally

test.flux.loop:
	$(call log.test, Testing..)
	./compose.mk flux.loop/2/io.time.wait/1

test.flux.each:
	$(call log.test, Testing flux.each)
	printf "one\ntwo"|./compose.mk flux.each/flux.echo
test.flux.pipe.fork:
	$(call log.test, Testing flux.pipe.fork)
	echo hello-world | targets="stream.echo,stream.echo" ./compose.mk flux.pipe.fork
	echo hello-world | ./compose.mk flux.pipe.fork/stream.echo,stream.echo

test.flux.pipe:
	$(call log.test, Testing flux.pipe.fork)
	echo hello-world | targets="stream.echo,stream.echo" ./compose.mk flux.pipe.fork
	echo hello-world | ./compose.mk flux.pipe.fork/stream.echo,stream.echo

test.flux.retry:
	$(call log.test, Testing..)
	! interval=1 ./compose.mk flux.retry/3/flux.fail

test.flux.apply:
	$(call log.test, Testing..)
	./compose.mk flux.apply/flux.echo,THUNK ${stream.obliviate}

test.flux.starmap:
	$(call log.test, Testing..)
	./compose.mk flux.starmap/flux.echo,flux.echo/bonk ${stream.obliviate}

test.flux.apply.later:
	$(call log.test, Testing..)
	./compose.mk flux.apply.later/2/io.time.wait/1 ${stream.obliviate}

test.flux.mux:
	$(call log.test, Testing..)
	targets="io.time.wait,io.time.wait,io.time.wait/4" ./compose.mk flux.mux  | jq .
	targets="io.time.wait,io.time.wait,io.time.wait/2" ./compose.mk flux.join | jq .
	./compose.mk flux.mux/io.time.wait

test.docker.run:
	$(call log.test, Checking)
	img=debian/buildd:bookworm ./compose.mk docker.dispatch/flux.ok
	echo hello-python-docker1 | ${make} .test.docker.run.def
	echo hello-python-docker2 \
	| entrypoint=cat cmd=/dev/stdin img=python:3.11-slim-bookworm ./compose.mk docker.run.sh
	entrypoint=python cmd='--version' \
		img=python:3.11-slim-bookworm ./compose.mk docker.run.sh
	echo {} | cmd=. img=ghcr.io/jqlang/jq:1.7.1 ./compose.mk docker.start
.test.docker.run.def:
	entrypoint=python def=script.demo.docker.run.def \
	img=python:3.11-slim-bookworm ${make} docker.run.def
define script.demo.docker.run.def 
# python script 
import sys
print(['input',sys.stdin.read().strip()])
endef
