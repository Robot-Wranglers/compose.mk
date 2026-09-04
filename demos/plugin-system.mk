#!/usr/bin/env -S make -f
#
# plugin-system.mk:
#   Same `include.plugins` call: the `.mk` plugin is `include`d verbatim
# (fast); the `.cmk` plugin is JIT-compiled (lowered) then included.
# cmk-lang plugins lower the same way from a `make` invocation as from
# `cmk run`. USAGE: ./demos/plugin-system.mk

include compose.mk

$(call include.plugins, prefix=demos/cmk/plugins plain.mk hello.cmk)

__main__: plugin.plain plugin.hello
