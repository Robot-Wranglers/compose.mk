# demos/just.mk: 
#   Demonstrates some interoperability with `just`.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/inlined-composefile.mk
#
#   This demo is structured so as to be self-contained, so at the start we have to
#   ensure that we can call a containerized version of `just`, and that we actually 
#   have a justfile available.

.DEFAULT_GOAL := demo.just

include compose.mk

# No official container https://github.com/casey/just/issues/1497
# So we have to clutter up the demo by building one >:( 
define inlined.just.service
services:
  just.container:
    build:
      context: .
      dockerfile_inline: |
        FROM alpine
        RUN apk add --update just bash alpine-sdk
    entrypoint: just
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
endef

define inlined.justfile
recipe-name:
  echo 'This is a recipe!'

# this is a comment
another-recipe:
  @echo 'This is another recipe.'
endef 

# After the inline exists, call `compose.import.def` on it.
$(eval $(call compose.import.def,  ▰,  TRUE, inlined.just.service))

# Main entrypoint.  
# We have to use the generated service-target to get access to `just`
# and write the justfile to disk to work with it.  Since `just` is only 
# available inside the container, we dispatch the `just.run` target there.
demo.just: \
  just.container/build mk.def.to.file/inlined.justfile/justfile \
  ▰/just.container/just.run just.another.recipe

# This target runs inside the container, so we can safely access `just`
just.run:
	just --help 
	just --list
	just another-recipe
	just
	
# An example of a just/make bridge, effectively 
# "importing" the justfile entrypoints to `make`
just.bridge/%:; ${make} ▰/just.container/just.run.target/${*}
just.run.target/%:; just ${*}
just.recipe: just.bridge/recipe-name
just.another.recipe: just.bridge/another-recipe
