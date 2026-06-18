#!/usr/bin/env -S make -f
# bind-file.mk:
#   Binding a file directly to a target.
#
# USAGE: ./demos/r.mk

include compose.mk

export foo=foo
export bar=var1

__main__:; $(call polyglot.bind.file, \
	img=python:3.11-slim-bookworm \
	file=demos/data/test-file.py \
	env='foo bar' entrypoint=python cmd='-O')