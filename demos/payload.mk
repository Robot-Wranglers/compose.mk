#!/usr/bin/env -S make -f
# Demonstrating guests, payloads, default services, and forks.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/guests.mk

include compose.mk

__main__: test.payload test.guest

payload={"hello":"world"}
default_services=demos/data/docker-compose.yml
guest_makefile=demos/no-include.mk

test.payload:
	${io.mktemp} && derived=$${tmpf} \
	&& $(call log.test, Setting payload works) \
	&& printf '${payload}' | ${make} mk.fork.payload > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep '${payload}' \
	&& $(call log.test, Result validates and executes) \
	&& chmod +x $${derived} && $${derived} flux.ok \
	&& $${derived} mk.def.read/PAYLOAD | ${jq} -e .hello

test.guest:
	${io.mktemp} && derived=$${tmpf} \
	&& $(call log.test, Setting guest works) \
	&& cat ${guest_makefile} \
		| ${make} mk.fork.guest > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep '^clean:' \
	&& $(call log.test, Result validates and executes) \
	&& chmod +x $${derived} && $${derived} flux.ok clean

test.services:
	${io.mktemp} && derived=$${tmpf} \
	&& $(call log.test, Setting services works) \
	&& cat ${default_services} | ${make} mk.fork.services > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep 'FROM $${IMG_DEBIAN_BASE:-debian:bookworm}' \
	&& $(call log.test, Result validates) \
	&& chmod +x $${derived} && $${derived} flux.ok
	&& $(call log.test, Services are loaded automatically) \
	&& ./$${derived} help | grep ubuntu.build
