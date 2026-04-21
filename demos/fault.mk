#!/usr/bin/env -S make -f
#
# fault.mk:
#   Demonstrating usage of the `fault.cmk` plugin, from plain Makefile.
# 
# Shows off the JIT compiler lowering CMK-lang to Makefile at parse time,
# so that the (foreign) plugin is still available at runtime.
#
# Loading fault.cmk upgrades the core `assert.env.var` in place: a failed
# assertion raises a typed EnvVarUnset fault that routes to a handler.
#
# USAGE:
#   ./demos/fault.mk               # tour: assert+guard, dispatched at exit
#   ./demos/fault.mk assert.demo   # one uncaught EnvVarUnset -> nonzero
#   REQUIRED=x ./demos/fault.mk    # assertion passes; only the guard fires

include compose.mk
$(call include.plugins, fault.cmk)

fault/EnvVarUnset:
	@# A typed handler -- beats the plugin's fault/%: fallback by make
	@# precedence.
	$(call fault.show)
	$(call fault.log, set ${bold}`echo "$${CMK_EVENT}" | ${jq.run} -r .var`${no_ansi}${red} and retry)

assert.demo:
	$(call log, asserting REQUIRED is present)
	$(call assert.env.var, REQUIRED)

guarded.demo:
	@# A raw subprocess failure bridged to a typed fault.  In a plain Makefile
	@# the `@` decorator isn't available (no compiler on this file), so append
	@# the guard macro by hand -- exactly what the decorator lowers to.
	$(call log, simulating a tool failure)
	sh -c 'exit 3' || { $(fault.guarded) }

# NB: a plain `make -f` does not run the compose.mk bash supervisor, so the
# at-exit drain that fault.cmk opts into won't fire on its own here.  The
# portable plain-make idiom is a synchronous drain at a chosen barrier
# (here, end of the run); a supervised runtime gets the at-exit drain for
# free, even on uncaught faults.

__main__:
	@# The tour: run each thrower as a sub-make and swallow it (`|| true`) so
	@# the event stays in flight, then drain explicitly.
	$(call log, plain-make consumer of fault.cmk)
	${make} assert.demo </dev/null || true
	${make} guarded.demo </dev/null || true
	${make} fault.dispatch.by_type
