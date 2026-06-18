#!/usr/bin/env -S ./compose.mk mk.interpret
# subcommands.mk:
#   A minimal subcommand CLI built on the reusable `cli.subcommands` engine.
#
# USAGE: (non-parametric subcommands)
#   ./demos/subcommands.mk greet world       # -> hello world
#   ./demos/subcommands.mk greet me          # -> hello <user>
#
# USAGE: (parametric subcommands)
#   ./demos/subcommands.mk greet hello bob   # -> hello, bob!
#
# USAGE: (help)
#   ./demos/subcommands.mk greet             # -> usage
#   ./demos/subcommands.mk greet help        # -> usage
#   ./demos/subcommands.mk                   # -> usage
#
# NB: Subcommand dispatch requires a supervisor (see shebang); not `make -f`.
#
include compose.mk

# The whole CLI: one line, fully auto-detected. 
# By default, namespaces come from the target name, and
# subcommands are reflected from the `.greet.*` handlers below.
greet:; $(call cli.subcommands.enter)
.greet.world:; printf 'hello world\n'
.greet.me:;    printf "hello $${USER}"
.greet.hello/%:; printf 'hello, %s! (argv=%s)\n' "${*}" "$${argv:-}"


__main__: greet
