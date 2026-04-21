#!/usr/bin/env -S make -f
#
# import-file.mk: Importing a file directly to a target as a code-object.
#
# USAGE: ./demos/import-file.mk

include compose.mk

export foo=val1
export bar=val2

# A file-sourced code-object: `file=` provides the body, img=/entrypoint= bind
# it to a container, so running the `testing` target runs the file inside it.
$(call code, def=testing file=demos/data/test-file.py img=python:3.11-slim-bookworm entrypoint=python cmd=-O env='foo bar')

__main__: testing
