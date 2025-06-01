#!/usr/bin/env -S make -f
# demos/inlined-composefile.mk: 
#   Demonstrates working with inlined compose-files via `_compose.import.string`,
#   which works exactly like `compose.import`, but accepts embedded data instead of files.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   USAGE: ./demos/inlined-composefile.mk

include compose.mk

# Look it's an embedded compose file.  This defines services `alice` & `bob`
define inlined.services 
services:
  alice: &base
    hostname: alice
    build:
      context: .
      dockerfile_inline: |
        FROM ${IMG_DEBIAN_BASE:-debian:bookworm-slim}
        RUN apt-get update -qq && apt-get install -qq -y make procps
    entrypoint: bash
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
  bob:
    <<: *base
    hostname: bob
    build:
      context: .
      dockerfile_inline: |
        FROM ${IMG_ALPINE_BASE:-alpine:3.22}
        RUN apk add -q --update --no-cache coreutils build-base bash procps-ng wget
        # Download and compile make 4.3
        RUN wget http://ftp.gnu.org/gnu/make/make-4.3.tar.gz
        RUN tar -xzf make-4.3.tar.gz
        #RUN cd make-4.3; ./configure && make && make install
endef 

# After the inline, just call `compose.import.string` on it to 
# build target scaffolding.  See instead `compose.import` for 
# using an external file.
$(call compose.import.string, def=inlined.services)

# Top level entrypoint, run the other individual demos.
__main__: demo.compose_verbs demo.dispatch

# Import has already modified the `inlined.services` namespace 
# with familiar verbs from docker compose, like "build", "stop",
# "ps", etc.  Now we can use them.
demo.compose_verbs: inlined.services.stop inlined.services.build

# Dispatch examples: run a task inside alice-container and bob-container.
# Note that docker build is implicit, on-demand, and cached unless forced.
demo.dispatch: \
	alice.dispatch/self.internal_task \
	bob.dispatch/self.internal_task
self.internal_task:
	echo "Running inside `hostname`"