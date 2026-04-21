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

plugins plugin-test:
	@# The .cmk/ plugin suite -- every plugin imports cleanly + exposes its public surface, plus the
	@# per-plugin behavior suites (repl/vm/polyglot).  Polyglot build+run cases need a docker daemon.
	tox -e plugin

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
	@# Target-level coverage report (report-only; the canonical full pass:
	@# unit+docker+integration+compiler+plugin, no smoke -- it adds no targets the
	@# other suites don't already cover).  Coverage is recorded PER TEST on EVERY
	@# run now: each test's slice is replaced when it runs and other slices are
	@# kept, so any subset refreshes exactly its own tests -- e.g. a bare
	@# `pytest -m docker` (or even `pytest -k foo`) merges just those tests into
	@# .coverage.json, and a stale credit self-corrects the next time that test
	@# runs.  This canonical env RESETS + runs the whole matrix in one session for
	@# single-run provenance.  Opt a run OUT with CMK_TEST_COVERAGE=0; wipe with
	@# CMK_COVERAGE_RESET=1 (or `rm tests/.coverage.json`).
	@# `.coverage.json` is the canonical artifact; re-render the human-readable
	@# summary (tests/coverage.md) from it once the run finishes.  Non-fatal: the
	@# JSON is already written, so a missing renderer just skips the convenience view.
	tox -e coverage
	@$(MAKE) -C .. docs.render/tests/coverage.md.j2 >/dev/null 2>&1 \
	  && echo "coverage: re-rendered tests/coverage.md from .coverage.json" \
	  || echo "coverage: skipped tests/coverage.md render (renderer unavailable)"

installers-test:
	@# Build+install via each packaging path; verify a global on-PATH compose.mk.
	tox -e pip-installer
	tox -e npm-installer
	tox -e basher-installer
	tox -e docker-installer

perf perf-test:
	@# Cold-start perf benchmark (report-only; opt-in, not wired to CI).
	tox -e perf-test
