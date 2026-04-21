#!/usr/bin/env -S make -f
#
# callforms.mk:
#   The ways to call compose.mk's library functions: nullary macro
#   expansion, parametric `$(call ..)`, and the macro-vs-target equivalence
#   -- many targets also publish a same-named macro, which saves a process
#   and avoids a recursive re-parse.
#
#   See the Call Forms section of the compiler docs:
#   https://robot-wranglers.github.io/compose.mk/cmk/compiler/#call-forms
#
# USAGE: ./demos/callforms.mk

include compose.mk

__main__: nullary parametric macro_form target_form

nullary:
	@# Nullary expansion (no arguments): just reference the macro.
	printf '{"a":1}\n' | ${stream.peek} | ${jq} .

parametric:
	@# Parametric helpers take arguments via a make call-form.
	$(call log, starting up)

macro_form:
	@# Macro form: expands inline (one fewer process, no recursive re-parse).
	printf 'a\nb\n' | ${stream.nl.to.space}

target_form:
	@# Target form: equivalent to the macro form, but a recursive `make` call.
	printf 'a\nb\n' | ${make} stream.nl.to.space
