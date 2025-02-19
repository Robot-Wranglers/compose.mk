#!/usr/bin/env -S bash -x -euo pipefail
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.
#
# USAGE: bash -x tests/docker-utilities.sh

# show docker version info
./compose.mk docker.init

# build a Dockerfile to a tag
tag=testing ./compose.mk docker.from.file/demos/data/Dockerfile

# run an image with a command
img=testing entrypoint=sh cmd='-c ls' ./compose.mk docker.run.sh

# run a target inside an image
img=testing ./compose.mk docker.run/flux.ok

# show help for the docker.images target
./compose.mk help docker.images

# show images that are managed by compose.mk
./compose.mk docker.images 

# show all docker images
./compose.mk docker.images.all