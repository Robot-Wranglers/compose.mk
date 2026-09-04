#!/usr/bin/env -S make -f
#
# inlined-cmk.mk:
#   Embedding CMK-Lang in a vanilla Makefile (stock make -f, no CMK
#   shebang).  Only the Report define is compiled: import.module lowers
#   that one block on import, and the host Makefile stays plain make.
#
# USAGE: ./demos/inlined-cmk.mk

include compose.mk

# A plain-make target: not CMK-Lang, never compiled, run by stock make.
plain:; $(call log, plain target left to stock make)

# Report: ( CMK-Lang embedded in a plain Makefile define )
#   The heredoc literals and this.-dialect calls are lowered by mk.compile
#   on import; everything outside the define is left to stock make.
define Report
report:
	@# two ways to send a heredoc literal to a stream target
	"""piped in""" | this.stream.as.log
	this.stream.as.log["""and via the bracket receiver form"""]
endef
$(call import.module, def=Report flat=1)

# Run both: the untouched plain target, then the compiled report.
__main__: plain report
