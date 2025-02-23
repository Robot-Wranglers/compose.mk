# demos/inlined-composefile.mk: 
#   Demonstrates working with inlined compose-files via `compose.import.define`,
#   which works exactly like `compose.import`, but accepts embedded data instead of files.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/inlined-composefile.mk

include compose.mk
.DEFAULT_GOAL := demo.inline

# Look it's an embedded compose file.  This defines services `alice` & `bob`
define inlined.composefile 
services:
  alice: &base
    hostname: alice
    build:
      context: .
      dockerfile_inline: |
        FROM debian:bookworm
        RUN apt-get update && apt-get install -y make procps
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
        FROM alpine:3.21.2
        RUN apk add --update --no-cache coreutils alpine-sdk bash procps-ng
endef 

# After the inline exists, just call `compose.import.define` on it.
$(eval $(call compose.import.def, inlined.composefile,  TRUE))

# Now you can use the service target scaffolding, 
# dispatching tasks inside containers, etc
demo.inline: alice.dispatch/internal_task bob.dispatch/internal_task

internal_task:
	echo "Running inside `hostname`"
