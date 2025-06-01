#!/usr/bin/env -S make -f
# Demonstrating binding a file directly to a target.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/r.mk

include compose.mk

export foo=foo
export bar=var1

__main__:; $(call polyglot.bind.file, \
	img=python:3.11-slim-bookworm \
	file=demos/data/test-file.py \
	env='foo bar' entrypoint=python cmd='-O')