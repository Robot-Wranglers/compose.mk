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
.PHONY: README.md demos/cmk/README.md demos/README.md

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})
export MKDOCS_LISTEN_PORT=8005
include compose.mk
__main__: init clean build test docs

py.release.root := via/pip
$(call include.plugins, actions.mk docs.cmk drawio.cmk mmd.cmk grip.cmk mkdocs.cmk html.cmk gitops.cmk py.mk)
$(call include.plugins, prefix=. .automation.cmk)
$(call include.plugin, file=local.mk strict=0)
$(call compose.import, file=demos/data/docker-compose.yml)

init: mk.stat docker.stat gitops.hooks.init
	@# Show status, initialize some containers, and wire git hooks (see gitops.hooks.precommit/*).

# Register the reusable gitleaks secret-scan (gitops.cmk) as a pre-commit hook; declaring this
# target IS the registration -- `make gitops.hooks.init` (run by `init`) reflects it into a real
# .git/hooks/pre-commit.  Bypass a commit's hooks with `git commit --no-verify`.
gitops.hooks.precommit/gitleaks: gitops.gitleaks


#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Docs: the pipeline (target `docs`) lives in docs.cmk and runs the same locally and in
# CI (.github/workflows/docs.yml calls `make docs`).  Only the project bindings are here:
# which files are README mirrors, and the plugin-doc-sync allow-list policy.

README.md:; ${docs.render.mirror}
demos/cmk/README.md:; ${docs.render.mirror}
demos/README.md:; ${docs.render.mirror}
docs.mirrors: README.md demos/README.md demos/cmk/README.md

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
validate: validate.makefiles validate.tests
	@# Validate all demos (syntax) and the test-suite (style/lint).

validate.tests:
	@# Auto-fix + lint the Python test-suite (ruff via tox; combined fix+check).
	@# Only needed when you change files under tests/.
	pushd tests && make init normalize

validate.markdown/%:; ${make} docs.render.io/${*},/dev/null
validate.makefiles:
	@# 
	ls demos/*[.]mk | ./compose.mk flux.each/mk.validate
	ls demos/tui/*[.]mk | ./compose.mk flux.each/mk.validate

clean: stage.clean
	@# Only used during development; normal usage involves build-on-demand.
	@# Cache-busting & removes temporary files used by build / tests 
	rm -f tests/compose.mk
	find . | grep .tmp | xargs rm 2>/dev/null || true

build: tux.require
	@# Containers are normally pulled on demand, 
	@# but pre-caching cleans up the build logs.
	${jb} foo=bar | ${jq} . > /dev/null

normalize: # NOP
# pygments.nord: pygments.css/nord-darker
# pygments.css/%:; pygmentize -S ${*} -f html 
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

test: validate unit-test plugin-test compiler-test docker-test integration-test demos smoke-test
	@#

utest unit-test:
	@# Runs the integration-test suite.
	pushd tests && make init unit-test

ptest plugin-test:
	@# Runs the .cmk/ plugin suite (delegates to tests/).
	pushd tests && make init plugin-test

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

perftest perf-test:
	@# Cold-start perf benchmark (report-only; opt-in; delegates to tests/).
	pushd tests && make init perf-test

demos demos.test demo-test:
	@# 
	set -x && ls demos/*.mk | xargs -I% ${io.shell.isolated} sh -x -c "head -1 % | grep -q '^#!' || { echo 'MISSING SHEBANG (refusing sh-fallback): %' >&2; exit 255; }; ./% || exit 255"
	# set -x && ls demos/*.mk |grep -v lean| xargs -I% bash -x -c "head -1 % | grep -q '^#!' || { echo 'MISSING SHEBANG (refusing sh-fallback): %' >&2; exit 255; }; ./% || exit 255"

demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

docs.agent:
	@# 
	mv docs/img docs.img \
	; archive='docs demos' bin=docs.agent ./demos/cmk/rag.cmk mk.pkg.root \
	; mv docs.agent docs/artifacts \
	; mv docs.img docs/img

serve: docs.serve
	@# Runs the mkdocs server (live preview) from the docs render container

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
$(call include.plugins, gitops.cmk)
gitops.watch := docker-publish.yml release-ci.yml
gitops.ci.workflows := release-ci.yml
gitops.clean_check := 0
gitops.release.assert.version: assert.env/VERSION
	@# Release guard: the tag being cut must equal the baked CMK_VERSION, so a released
	@# compose.mk self-reports the right semver.  Bump CMK_VERSION in compose.mk (commit)
	@# before releasing.  Auto-discovered + run among the gitops.release.* helpers (flux.star);
	@# a mismatch fails the helper, which aborts the release before the tag is cut.
	if [ "$${VERSION}" != "${CMK_VERSION}" ]; then \
		$(call log.io, ${red}Error:${no_ansi} VERSION=$${VERSION} != baked CMK_VERSION=${CMK_VERSION} -- bump CMK_VERSION in compose.mk and commit, then release); \
		exit 1; \
	fi \
	&& $(call log.io, ${green}version ok ${sep} ${CMK_VERSION})
actions.demos:
	@# Entrypoint for test-action
	${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"
actions.demos.cmk:
	@# CI-only entrypoint for the on-demand full sweep of every CMK-lang demo
	@# (heavy/GUI/LLM demos included).  The push/PR gate for CMK demos is the pytest
	@# suite (tests/test_integration_cmk.py); this is the manual safety net.
	set -x && ls demos/cmk/*.cmk | xargs -I% ${io.shell.isolated} sh -x -c "head -1 % | grep -q '^#!' || { echo 'MISSING SHEBANG (refusing sh-fallback): %' >&2; exit 255; }; ./% || exit 255"
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
