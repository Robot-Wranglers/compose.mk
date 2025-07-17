#!/usr/bin/env -S make -f
# Demonstrating importing a file directly to a target.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/import-file.mk

include compose.mk

export foo=val1
export bar=val2

kwargs= \
	file=demos/data/test-file.py \
	img=python:3.11-slim-bookworm \
	entrypoint=python cmd='-O' \
	namespace=testing \
	env='foo bar'

$(call polyglot.import.file, ${kwargs})

__main__: testing