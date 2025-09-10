#!/usr/bin/env -S make -s -S -f 
##
# Project Automation
#
# Typical usage: `make clean build test`
##
SHELL := bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
THIS_MAKEFILE:=$(abspath $(firstword $(MAKEFILE_LIST)))

.PHONY: docs demos demos/cmk README.md docs.agent

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})

include compose.mk
$(call mk.import.plugins, actions.mk docs.mk)
$(call mk.import.plugin.maybe, local.mk)
$(call compose.import, file=demos/data/docker-compose.yml)

__main__: init clean build test docs

init: mk.stat docker.stat
validate: validate.makefiles validate.markdown
docs: flux.stage/documentation docs.README.static docs.jinja docs.pynchon.dispatch/.docs.build
.docs.build:
	$(call log.target, building)
	set -x && (mkdocs build --clean --verbose && tree site) \
	; find site docs | xargs chmod o+rw; ls site/index.html

# Mirroring templated files to untemplated ones elsewhere in the repository.
.PHONY: README.md demos/cmk/README.md demos/README.md
README.md:; ${docs.render.mirror}
demos/cmk/README.md:; ${docs.render.mirror}
demos/README.md:; ${docs.render.mirror}
docs.README.static: README.md demos/README.md demos/cmk/README.md

validate.markdown:
	${make} docs.jinja_templates \
	| ${stream.fold} | ${stream.peek} \
	| ${stream.space.to.nl} \
	| ${io.xargs.verbose} "${make} validate.markdown/%"
validate.markdown/%:; pynchon jinja render ${*}
validate.makefiles:
	ls demos/*[.]mk | ./compose.mk flux.each/mk.validate
	ls demos/tui/*[.]mk | ./compose.mk flux.each/mk.validate

clean: flux.stage.clean
	@# Only used during development; normal usage involves build-on-demand.
	@# Cache-busting & removes temporary files used by build / tests 
	rm -f tests/compose.mk
	find . | grep .tmp | xargs rm 2>/dev/null || true

build: tux.require
	@# Containers are normally pulled on demand, 
	@# but pre-caching cleans up the build logs.
	${jb} foo=bar | ${jq} .

normalize: # NOP
pygments.nord: pygments.css/nord-darker
pygments.css/%:; pygmentize -S ${*} -f html 

test: validate integration-test demos smoke-test 
itest integration-test:; ./demos/itest.mk
	@# Runs the integration-test suite.

stest smoke-test:
	@# Runs the smoke-test suite
	ls tests/*.sh | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demos demos.test demo-test:
	set -x && ls demos/*.mk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"
	# set -x && ls demos/*.mk |grep -v lean| xargs -I% bash -x -c "./% || exit 255"

demos/cmk:
	set -x && ls demos/cmk/*.cmk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

docs.agent:
	mv docs/img docs.img \
	; archive='docs demos' bin=docs.agent ./demos/cmk/rag.cmk mk.pkg.root \
	; mv docs.agent docs/artifacts \
	; mv docs.img docs/img

actions.demos:
	@# Entrypoint for test-action
	${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"

serve: docs.serve