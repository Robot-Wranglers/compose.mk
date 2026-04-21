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
	tox -e fix,normalize

units unit-test:
	@# Fast, no-docker unit tests (stream.* and friends).
	tox -e unit
