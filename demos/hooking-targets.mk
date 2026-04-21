#!/usr/bin/env -S ./compose.mk mk.interpret
#
# hooking-targets.mk:
#   Using compose.mk as an alternate interpreter for make.
#   This example shows automatic installation of pre/post hooks.
#
# USAGE: ./demos/hooking-targets.mk main_target
#

main_target.pre:; echo hello pre-hook
main_target:; echo hello main
main_target.post:; echo hello post-hook

flux.ok.pre:; echo look, hooking a builtin works too

__main__:; $(call log.base,${red} USAGE: ${__file__} main_target)
