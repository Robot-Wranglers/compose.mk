#!/usr/bin/env -S make -f
# module-system.mk -- plain-make MIRROR of demos/cmk/module-system.cmk.
# USAGE: ./demos/module-system.mk

include compose.mk

define MyModule
var1:=val1

target.simple: io.env/CMK_MODULE
	@# A simple target in pure make, part of a module.
	@# The `io.env/...` above demonstrates that is
	@# automatically injected into the current context.
	$(call log.target, module=$${CMK_MODULE:-})

target.cmk:
	@# A CMK-Lang target.  By default modules are compiled, so the
	@# `"""..."""` heredoc and `this.` dialect below are lowered.
	"""hello compiler""" | this.stream.preview
endef

$(call mk.import.module, def=MyModule)

__main__: MyModule.target.simple MyModule.target.cmk
