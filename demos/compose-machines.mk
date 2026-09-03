#!/usr/bin/env -S make -f
#
# compose-machines.mk: 
#   compose services as machines
#
# USAGE: ./demos/compose-machines.mk

include compose.mk

# One service (omit usual `services:` key)
define alpha
image: alpine:3.21.2
entrypoint: sh
volumes:
  - /tmp:/host-tmp
endef

# Scaffolds targets, plus the machine ambient
$(call compose.service, def=alpha)

# Whole verbatim compose file
define pair
services:
  left:
    image: alpine:3.21.2
    entrypoint: sh
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
  right:
    image: debian:bookworm-slim
    entrypoint: sh
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
  daemon:
    image: alpine:3.21.2
    entrypoint: ["sleep", "infinity"]
endef

# Scaffold many service targets, plus the machine-ambients
$(call compose.group, def=pair)

# A small script to run
define alpine.probe
  cat /etc/alpine-release
  test -d /workspace && echo defaults merged
  test -d /host-tmp && echo body volumes merged
endef

define alpine.release
  cat /etc/alpine-release
endef

define debian.release
  cat /etc/debian_version
endef

__main__: demo.in demo.group demo.classic

# Block runs inside the service, not on the host.
demo.in: alpha.exec/alpine.probe

# Each service in the group is a machine of its own.
demo.group: left.exec/alpine.release right.exec/debian.release

# Access by individual or by group.
demo.classic: \
  alpha.services pair.images \
	pair.daemon.up.detach \
	pair.daemon.ps pair.daemon.clean

# Shows the generated compose files, no docker needed.
render: alpha.render pair.render
