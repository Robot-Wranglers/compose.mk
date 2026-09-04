#!/usr/bin/env -S make -f
#
# bind-file.mk: Binding a file directly to a target as a code-object.
#
# USAGE: ./demos/bind-file.mk

include compose.mk

export foo=foo
export bar=var1

# A file-sourced code-object bound to a python container.  Making it a
# prerequisite of __main__ runs the file when the demo runs.
$(call code, def=bound_script file=demos/data/test-file.py img=python:3.11-slim-bookworm entrypoint=python cmd=-O env='foo bar')

__main__: bound_script
