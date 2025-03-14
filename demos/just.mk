#!/usr/bin/env -S make -f
# demos/just.mk: 
#   Demonstrates some interoperability with `just`.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/inlined-composefile.mk
#

include compose.mk
.DEFAULT_GOAL := demo.just

# No official container https://github.com/casey/just/issues/1497
# So we have to clutter up the demo by building one :( 
define just.services
services:
  just_container:
    build:
      context: .
      dockerfile_inline: |
        FROM alpine
        RUN apk add -q --update just bash alpine-sdk
    entrypoint: just
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
endef

# Example justfile, inlined to stay self-contained.
# See also: https://github.com/casey/just/#quick-start
define just.justfile
recipe-name:
  echo 'This is a recipe!'

# this is a comment
another-recipe:
  @echo 'This is another recipe.'
endef 

# After the inline exists, call `compose.import.string` on it.
$(eval $(call compose.import.string,  just.services))

# Main entrypoint.  
# We have to use the generated service-target to get access to `just`
# and write the justfile to disk to work with it.  Since `just` is only 
# available inside the container, we dispatch the `just.run` target there.
demo.just: \
  demo.init \
  just_container.dispatch/just.run \
  just.recipe \
  just.another.recipe

# writes the justfile to disk so we can work with it
demo.init: mk.def.to.file/just.justfile/justfile 

# Example target that runs inside the container, so we can safely access `just`
just.run: just.list
	just --version 
	just another-recipe
	just
just.list:; just --summary
demo.list: just_container.dispatch/just.list

# Stacking 2 layers of dispatch is a bridge!, 
# effectively importing all the justfile targets 
# to top-level `make`.  This allows access to 
# justfile targets from the host, which doesn't
# actually have `just`.
just.dispatch/%:; just ${*}
demo.bridge/%:; ${make} just_container.dispatch/just.dispatch/${*}


# Having setup the bridge, we can use it-- 
# You can alias existing targets, or stack them 
# up as prerequisite targets as usual, etc
just.recipe: demo.bridge/recipe-name
just.another.recipe: demo.bridge/another-recipe


# The bridge also allows us to compose brand new functionality really quickly.
# As an example, below we provide an interactive runner for the justfile that 
# lets us choose which target to kick off.  To do this, we can use the 
# `io.selector` gadget, which just expects a "get choices" target a 
# "use chosen" handler target, and we already have both.
justfile.target.selector: demo.init io.selector/demo.list,demo.bridge


