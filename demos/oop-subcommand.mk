#!/usr/bin/env -S ./compose.mk mk.interpret
#
# oop-subcommand.mk:
#   (Ab)using the subcommand-namespace MRO to simulate OOP inheritance.
#   The `pet` CLI searches its namespaces in order (`.puppy`, then `.dog`,
#   then `.animal`), exactly like a method-resolution order: a sub defined
#   in a more-derived "class" overrides the base, and subs that only a base
#   defines are inherited.
#
# USAGE:
#   ./demos/oop-subcommand.mk pet speak        # -> yip!  (.puppy over .dog/.animal)
#   ./demos/oop-subcommand.mk pet fetch        # -> ...   (inherited from .dog)
#   ./demos/oop-subcommand.mk pet legs         # -> 4     (inherited from .animal)
#   ./demos/oop-subcommand.mk pet describe rex # -> ...   (inherited, parametric)
#   ./demos/oop-subcommand.mk pet              # -> usage
#
# NB: Subcommand dispatch requires a supervisor (see shebang); not `make
# -f`.
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

# the MRO, most-derived first.  `pet speak` resolves to `.puppy.speak`;
# `pet fetch` falls through to `.dog.fetch`; `pet legs`/`pet describe` fall
# through to `.animal.*`.
pet:; $(call cli.subcommands.enter, namespace='.puppy .dog .animal')

__main__: pet
