#!/usr/bin/env -S bash -x -euo pipefail
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
# USAGE: bash -x tests/docker-utilities.sh

# show docker version info
./compose.mk docker.init

# show docker status
./compose.mk docker.stat

# build a Dockerfile to a tag
tag=debian/buildd:bookworm  ./compose.mk docker.from.file/demos/data/Dockerfile

# run an image with a command
img=debian/buildd:bookworm  entrypoint=sh cmd='-c ls' ./compose.mk docker.run.sh

# run a target inside an image
img=debian/buildd:bookworm ./compose.mk docker.dispatch/flux.ok

# show help for the docker.images target
./compose.mk help docker.images

# show images that are managed by compose.mk
./compose.mk docker.images 

# show all docker images
./compose.mk docker.images.all

# like docker ps, but always returns JSON
./compose.mk docker.ps