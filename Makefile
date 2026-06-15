##
# Project Automation
#
# Typical usage: `make clean build test`
# Ultraclean: `make tux.purge tux.require`
##
SHELL := bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
THIS_MAKEFILE:=$(abspath $(firstword $(MAKEFILE_LIST)))

.PHONY: docs demos README.md docs.agent

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export MKDOCS_LISTEN_PORT=8005
include compose.mk
$(call mk.import.plugins, actions.mk docs.mk)
$(call mk.import.plugin, file=local.mk strict=0)
$(call compose.import, file=demos/data/docker-compose.yml)

__main__: init clean build test docs

init: mk.stat docker.stat 
	@# Show status and initialize some containers

validate: validate.makefiles validate.tests
	@# Validate all demos (syntax) and the test-suite (style/lint).

validate.tests:
	@# Auto-fix + lint the Python test-suite (ruff via tox; combined fix+check).
	@# Only needed when you change files under tests/.
	pushd tests && make init normalize

docs: flux.stage/documentation docs.pynchon.build docs.README.static docs.jinja docs.pynchon.dispatch/.docs.build
	@# Build all documentation
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
	@#
# find ${docs.root} -name .j2 \
# | ${stream.fold} | ${stream.peek} \
# | ${stream.space.to.nl} \
# | ${io.xargs.verbose} "${make} validate.markdown/%"
validate.markdown/%:; pynchon jinja render ${*}
validate.makefiles:
	@# 
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
	${jb} foo=bar | ${jq} . > /dev/null

normalize: # NOP
pygments.nord: pygments.css/nord-darker
pygments.css/%:; pygmentize -S ${*} -f html 

test: validate unit-test compiler-test docker-test integration-test demos smoke-test
	@#

utest unit-test:
	@# Runs the integration-test suite.
	pushd tests && make init unit-test

ctest compiler-test:
	@# Runs the CMK compiler suite (pure; delegates to tests/).
	pushd tests && make init compiler-test

dtest docker-test:
	@# Runs the docker.* target suite (delegates to tests/).
	pushd tests && make init docker-test

cov coverage:
	@# Target-level coverage report (report-only; delegates to tests/).
	pushd tests && make init coverage

itest integration-test:
	@# Runs the integration-test suite (delegates to tests/).
	pushd tests && make init integration-test

tui-test:
	@# Runs the headless embedded-TUI suite (heavy/opt-in; delegates to tests/).
	pushd tests && make init tui-test

stest smoke-test:
	@# Runs the smoke-test suite (delegates to tests/).
	pushd tests && make init smoke-test

installers-test:
	@# Build+install the via/pip shim; verify a global on-PATH compose.mk.
	pushd tests && make init installers-test

ptest perf-test:
	@# Cold-start perf benchmark (report-only; opt-in; delegates to tests/).
	pushd tests && make init perf-test

demos demos.test demo-test:
	@# 
	set -x && ls demos/*.mk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"
	# set -x && ls demos/*.mk |grep -v lean| xargs -I% bash -x -c "./% || exit 255"

demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

docs.agent:
	@# 
	mv docs/img docs.img \
	; archive='docs demos' bin=docs.agent ./demos/cmk/rag.cmk mk.pkg.root \
	; mv docs.agent docs/artifacts \
	; mv docs.img docs/img

actions.demos:
	@# Entrypoint for test-action
	${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"

actions.demos.cmk:
	@# CI-only entrypoint for the on-demand full sweep of every CMK-lang demo
	@# (heavy/GUI/LLM demos included).  The push/PR gate for CMK demos is the pytest
	@# suite (tests/test_integration_cmk.py); this is the manual safety net.
	set -x && ls demos/cmk/*.cmk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

serve: docs.serve
	@# Runs the mkdocs server