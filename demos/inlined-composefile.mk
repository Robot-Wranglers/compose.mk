# demos/inlined-composefile.mk: 
#   Demonstrates `compose.import.define`.  
#   This works exactly like `compose.import`, but it accepts embedded data instead of files.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/inlined-composefile.mk

.DEFAULT_GOAL := demo.inline

include compose.mk

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
$(eval $(call compose.import.def,  ▰,  TRUE, inlined.composefile))

# So now you can use the automatically generated targets,
# and dispatch tasks inside containers.
demo.inline: alice/get_shell bob/get_shell ▰/alice/internal_task ▰/bob/internal_task

internal_task:
	echo "Running inside `hostname`"
