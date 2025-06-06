#!/usr/bin/env -S bash -x -euo pipefail
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
#
# USAGE: ./tests/cli-help.sh

# help with no arguments should lists targets.
./compose.mk help

# help for a specific target shows markdown docstrings, rendered from source
./compose.mk help docker.image.run

# help for a module docstring can be used like this
./compose.mk help docker

# this won't fail even though target doesn't exist (falls back to search)
./compose.mk help doesnt.fail

# All of the demos get `help.local` just by using `include compose.mk`
./demos/container-dispatch.mk help.local

# use `mk.include` reflection to generate help for a makefile with no `include compose.mk`
./compose.mk mk.include/./demos/no-include.mk help.local
