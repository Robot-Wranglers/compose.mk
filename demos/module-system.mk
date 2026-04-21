#!/usr/bin/env -S make -f
#
# module-system.mk:
#   Defines one module,
#   then imports it four ways -- aliased, partial, star-glob, and flat.  The
#   report target is CMK-Lang embedded in a plain Makefile, lowered at import
#   time by the default mk.compile preproc.
#
# USAGE: ./demos/module-system.mk

include compose.mk

# MyModule: ( one module, mixing plain-make and CMK-Lang targets )
#   Import rewrites only the declared target names; recipe bodies and
#   values are copied through untouched.
define MyModule
greet:; $(call log, hello)
svc.up:; $(call log, starting)
svc.down:; $(call log, stopping)
report:
	@# A CMK-Lang recipe -- heredoc and this.-dialect calls, lowered at import.
	"""compiled report ok""" | this.stream.preview
endef

# The same module, imported four ways -- each into a fresh namespace, so
# members land as namespace.target (the flat form goes straight to root).

# aliased -- namespace differs from the module name
$(call import.module, def=MyModule namespace=Aliased)
# partial -- only the greet target
$(call import.module, def=MyModule targets=greet namespace=Part)
# star -- the svc.* glob
$(call import.module, def=MyModule targets='svc.*' namespace=Star)
# root -- flat, no prefix, straight into root
$(call import.module, def=MyModule flat=1)

# One representative target from each import, run as prerequisites.
__main__: \
	Aliased.report Aliased.greet \
	Part.greet \
	Star.svc.up Star.svc.down \
	greet
