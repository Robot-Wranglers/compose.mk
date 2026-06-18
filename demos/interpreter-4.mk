#!/usr/bin/env -S ./compose.mk mk.interpret
# interpreter-4.mk:
#   Using compose.mk as an alternate interpreter for make.
#   This example shows automatic installation of pre/post hooks.
#
# USAGE: ./demos/interpreter-4.mk main_target
#

main_target.pre:; echo hello pre-hook
main_target:; echo hello main
main_target.post:; echo hello post-hook

flux.ok.pre:; echo look, hooking a builtin works too

__main__:; $(call log,${red} USAGE: ${__file__} main_target)
