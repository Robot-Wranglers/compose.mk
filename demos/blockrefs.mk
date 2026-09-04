#!/usr/bin/env -S make -f
#
# blockrefs.mk:
#   The two block-reference forms, hand-written in plain Make.  A
#   define-block keeps a snippet in one named place; here it is dropped
#   onto a command line with no temp-file juggling.  _mk.def.to.fd inside
#   a <(..) process-substitution gives an FD for stream consumers, and
#   _mk.def.tmpfile materializes a real, seekable file for tools that
#   need a path.
#
# USAGE: ./demos/blockrefs.mk

include compose.mk

define greeting
hello from a block
endef

via.stream:
	@# A process-substituted FD, for stream or stdin-style consumers.
	cat <($(call _mk.def.to.fd, greeting))

via.file:
	@# A real file on disk, for tools that must open or seek a path.
	wc -c $(call _mk.def.tmpfile, greeting)

__main__: via.stream via.file
