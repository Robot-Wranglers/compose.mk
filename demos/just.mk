#!/usr/bin/env -S make -f
# demos/just.mk: 
#   Demonstrates some interoperability with `just`.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/just.mk
#   USAGE: ./demos/just.mk justfile.target.selector
#

include compose.mk
.DEFAULT_GOAL := __main__
__main__: \
  just_container.dispatch/self.just.demo \
  just.recipe just.another.recipe

# No official container (https://github.com/casey/just/issues/1497), so we'll build one.
# Just to keep the demo self-contained, we embed a docker-compose spec for a container
# here, as well as the justfile that we'll use.  A bind-map or volume would be faster 
# and more practical here, but we won't need it.
define just.services
configs:
  justfile:
    content: |
      recipe-name:
        echo 'This is a recipe!'

      # this is a comment
      another-recipe:
        @echo 'This is another recipe.'
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
    configs:
      - source: justfile
        target: justfile
endef

# After the inline exists, we get access to scaffolded 
# container targets by calling  `compose.import.string` on it.
$(eval $(call compose.import.string,  just.services))

# A small container-api, considered "private". Targets below run inside the container,
# so we can directly use `just` here without assuming it is available on the host.
self.just.list:; just --summary
self.just.version:; just --version 
self.just.demo: self.just.list self.just.version
	just another-recipe
	just

# By making a dispatch alias, 
# you can "lift" the private target to a "public" one, 
# i.e. something that is safe to run on the docker host.
just.list: just_container.dispatch/self.just.list

# Stacking 2 layers of dispatch is a bridge! 
# Effectively importing all the justfile targets to top-level `make`.
# This neatly abstracts the container, so you can then expose the full underlying 
# tool API, or an opinionated subset, or create an API superset at this layer that 
# extends it.
demo.bridge/%:; ${make} just_container.dispatch/self.just.dispatch/${*}
self.just.dispatch/%:; just ${*}

# Having setup the bridge, we can use it-- you can alias existing targets, 
# or stack them up as prerequisite targets as usual, etc
just.recipe: demo.bridge/recipe-name
just.another.recipe: demo.bridge/another-recipe

# The bridge also allows us to compose brand new functionality really quickly.
# As an example, below we provide an interactive runner for the justfile that 
# lets us choose which target to kick off.  To do this, we can use the 
# `io.selector` gadget, which just expects a "get choices" target a 
# "use chosen" handler target, and we already have both.
justfile.target.selector: io.selector/just.list,demo.bridge


