#!/usr/bin/env -S make -f
#
# payload.mk: Guests, payloads, default services, and forks.
#
# USAGE: ./demos/guests.mk

include compose.mk

__main__: test.payload test.guest

payload={"hello":"world"}
default_services=demos/data/docker-compose.yml
guest_makefile=demos/no-include.mk

test.payload:
	$(call _io.mktemp, var=derived) \
	&& $(call log.test, Setting payload works) \
	&& printf '${payload}' | ${make} lang.src.fork.payload > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep '${payload}' \
	&& $(call log.test, Result validates and executes) \
	&& chmod +x $${derived} && $${derived} flux.ok \
	&& $${derived} mk.def.read/PAYLOAD | ${jq} -e .hello

test.guest:
	$(call _io.mktemp, var=derived) \
	&& $(call log.test, Setting guest works) \
	&& cat ${guest_makefile} \
		| ${make} lang.src.fork.guest > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep '^clean:' \
	&& $(call log.test, Result validates and executes) \
	&& chmod +x $${derived} && $${derived} flux.ok clean

test.services:
	$(call _io.mktemp, var=derived) \
	&& $(call log.test, Setting services works) \
	&& cat ${default_services} | ${make} lang.src.fork.services > $${derived} \
	&& $(call log.test, Check for new contents) \
	&& cat $${derived} | grep 'FROM $${IMG_DEBIAN_BASE:-debian:bookworm}' \
	&& $(call log.test, Result validates) \
	&& chmod +x $${derived} && $${derived} flux.ok
	&& $(call log.test, Services are loaded automatically) \
	&& ./$${derived} help | grep ubuntu.build
