#!/usr/bin/env -S bash -x -euo pipefail
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
#
# USAGE: bash -x tests/docker-utils.sh

# Shows docker version info
./compose.mk docker.init

# Shows docker status
./compose.mk docker.stat

# Shows newline-separated size details per repo / image.
./compose.mk docker.size.summary

# Create container from URL
url="https://github.com/alpine-docker/git.git#1.0.38:." \
    tag="alpine-git" ./compose.mk docker.from.url

# Construct URL from attributes
user=alpine-docker repo=git tag="1.0.38" ./compose.mk docker.from.github

# Build a Dockerfile to a tag
tag=compose.mk:testing ./compose.mk docker.from.file/demos/data/Dockerfile

# Failure if no tag is provided
! ./compose.mk docker.from.file/demos/data/Dockerfile

# Failure if file does not exist
! ./compose.mk docker.from.file/demos/data/Dockerfile.missing

# Run an image with a command
img=debian/buildd:bookworm  entrypoint=sh cmd='-c ls' ./compose.mk docker.run.sh

# Run a target inside an image
img=debian/buildd:bookworm ./compose.mk docker.dispatch/flux.ok

# Show help for the docker.images target
./compose.mk help docker.images

# Show images that are managed by compose.mk
./compose.mk docker.images 

# Show all docker images
./compose.mk docker.images.all

# Like docker ps, but always returns JSON
./compose.mk docker.ps