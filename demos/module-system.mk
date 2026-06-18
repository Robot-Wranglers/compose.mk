#!/usr/bin/env -S make -f
# module-system.mk:
#   Plain-make MIRROR of demos/cmk/module-system.cmk.
#
# Defines a module, then imports it FOUR ways (the cmk's `⦖ .. ⦕ as Aliased` is the
# `def=MyModule namespace=Aliased` call here).  The `"""..."""` report target is
# CMK-Lang, lowered at import by the default `mk.compile` preproc -- i.e. CMK
# embedded inside a plain Makefile.
# USAGE: ./demos/module-system.mk

include compose.mk

define MyModule
greet:; $(call log.target, hello)
svc.up:; $(call log.target, starting)
svc.down:; $(call log.target, stopping)
report:
	@# A CMK-Lang target -- the heredoc + `this.` dialect are lowered at import.
	"""compiled report ok""" | this.stream.preview
endef

$(call import.module, def=MyModule namespace=Aliased)              # 4. aliased -- namespace != module
$(call import.module, def=MyModule targets=greet namespace=Part)   # 1. partial -- only `greet`
$(call import.module, def=MyModule targets='svc.*' namespace=Star) # 2. star    -- the `svc.*` glob
$(call import.module, def=MyModule flat=1)                         # 3. root    -- flat, no prefix

__main__: \
	Aliased.report Aliased.greet \
	Part.greet \
	Star.svc.up Star.svc.down \
	greet
