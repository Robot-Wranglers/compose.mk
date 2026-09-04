#!/usr/bin/env -S ./compose.mk mk.interpret
#
# oop-subcommand.mk:
#   (Ab)using the subcommand-namespace search order to simulate
#   inheritance.  The pet CLI searches its namespaces most-derived
#   first, exactly like a method-resolution order: a sub defined
#   in a more-derived "class" overrides the base, and subs that only a base
#   defines are inherited.
#
# USAGE:
#   ./demos/oop-subcommand.mk pet speak
#   ./demos/oop-subcommand.mk pet fetch
#   ./demos/oop-subcommand.mk pet legs
#   ./demos/oop-subcommand.mk pet describe rex
#   ./demos/oop-subcommand.mk pet
#
# Note: subcommand dispatch requires a supervisor, so use the shebang.
#
include compose.mk

# base "class": animal
.animal.legs:;       printf '4\n'
.animal.speak:;      printf 'generic animal noise\n'
.animal.describe/%:; printf '%s is a kind of animal\n' "${*}"

# "subclass" dog (is-a animal): overrides speak, adds fetch
.dog.speak:; printf 'woof!\n'
.dog.fetch:; printf 'fetches the ball\n'

# "subclass" puppy (is-a dog): overrides speak again
.puppy.speak:; printf 'yip!\n'

# the resolution order, most-derived first
pet:; $(call cli.subcommands.enter, namespace='.puppy .dog .animal')

__main__: pet
