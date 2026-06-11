# Test-suite tooling for compose.mk.  See README.md for usage.
#
# All targets drive tox (tests/tox.ini), which provisions pytest + ruff into
# an isolated venv.  Run from here (`make`) or from the repo root via the
# delegating `unit-test` / `test` entrypoints.
SHELL := bash
.SHELLFLAGS := -euo pipefail -c

default: init unit-test
	@# Default: the full tox-based suite (style + unit).

tox: normalize units

init:
	@# Install tox (which provisions pytest/ruff into its own venv).
	which tox || ( \
		python3 -m pip install --upgrade tox \
			|| python3 -m pip install --user --upgrade tox)

normalize:
	@# Auto-apply ruff formatting + lint fixes, then verify (ruff via tox).
	@# Combined fix+check; also what root `validate.tests` runs.
	tox -e fix,normalize

units unit-test:
	@# Fast, no-docker unit tests (stream.* and friends).
	tox -e unit

smoke smoke-test:
	@# Smoke tests — wrap tests/scripts/*.sh and assert clean exit (needs docker).
	tox -e smoke

compiler-test:
	@# CMK compiler/transpiler tests (pure; no docker).
	tox -e compiler

docker-test:
	@# docker.* target suite (needs a daemon; cleanup is label-scoped).
	tox -e docker

integration-test:
	@# Integration suite — scaffolds a mini-project (needs a daemon).
	tox -e integration

tui tui-test:
	@# Headless embedded-TUI suite (heavy; builds compose.mk:tux; needs a daemon).
	@# Opt-in/on-demand; CMK_TEST_TUI=1 is set by the tox env.
	tox -e tui

coverage:
	@# Target-level coverage report (report-only; unit+docker+integration+compiler,
	@# no smoke -- it adds no targets the other suites don't already cover).
	tox -e coverage

installers-test:
	@# Build+install via each packaging path; verify a global on-PATH compose.mk.
	tox -e pip-installer
	tox -e npm-installer
	tox -e basher-installer
	tox -e docker-installer

perf perf-test:
	@# Cold-start perf benchmark (report-only; opt-in, not wired to CI).
	tox -e perf-test
