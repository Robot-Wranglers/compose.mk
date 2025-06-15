#!/usr/bin/env -S make -s -S -f 
##
# Project Automation
#
# Typical usage: `make clean build test`
##
SHELL := bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
THIS_MAKEFILE:=$(abspath $(firstword $(MAKEFILE_LIST)))

.PHONY: docs demos demos/cmk README.md docs.agent

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})

include compose.mk
$(eval $(call compose.import, demos/data/docker-compose.yml))
include .github/actions.mk
include docs/docs.mk
define docs.builder.composefile
services:
  docs.builder: &base
    hostname: docs-builder
    build:
      context: .
      dockerfile_inline: |
        FROM python:3.9.21-bookworm
        RUN pip3 install --break-system-packages pynchon==2025.3.20.17.28 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2 mkdocs-redirects==1.2.2
        RUN apt-get update && apt-get install -y tree jq
    entrypoint: bash
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
  mmd:
    hostname: mmd
    build:
      context: .
      dockerfile_inline: |
        FROM ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:10.6.1
        USER root 
        RUN apk add -q --update --no-cache coreutils build-base bash procps-ng
    working_dir: /workspace 
    volumes:
        - ${PWD}:/workspace
endef
$(eval $(call compose.import.string,  docs.builder.composefile,  TRUE))

__main__: init clean build test docs

init: mk.stat docker.stat
validate: validate.makefiles validate.markdown
validate.markdown:
	${make} docs.jinja_templates \
	| ${stream.fold} | ${stream.peek} \
	| ${stream.space.to.nl} \
	| ${io.xargs.verbose} "${make} validate.markdown/%"
validate.markdown/%:; pynchon jinja render $
validate.makefiles:
	ls demos/*[.]mk | ./compose.mk flux.each/mk.validate
	ls demos/tui/*[.]mk | ./compose.mk flux.each/mk.validate

clean: flux.stage.clean
	@# Only used during development; normal usage involves build-on-demand.
	@# Cache-busting & removes temporary files used by build / tests 
	rm -f tests/compose.mk
	find . | grep .tmp | xargs rm 2>/dev/null || true

build: tux.require
	@# Containers are normally pulled on demand, 
	@# but pre-caching cleans up the build logs.
	${jb} foo=bar | ${jq} .

normalize: # NOP
pygments.nord: pygments.css/nord-darker
pygments.css/%:; pygmentize -S ${*} -f html 

test: validate integration-test demos smoke-test 
itest integration-test:; ./demos/itest.mk
	@# Runs the integration-test suite.

stest smoke-test:
	@# Runs the smoke-test suite
	ls tests/*.sh | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demos demos.test demo-test:
	set -x && ls demos/*.mk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"
	# set -x && ls demos/*.mk |grep -v lean| xargs -I% bash -x -c "./% || exit 255"

demos/cmk:
	set -x && ls demos/cmk/*.cmk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

docs.agent:
	mv docs/img docs.img \
	; archive='docs demos' bin=docs.agent ./demos/cmk/rag.cmk mk.pkg.root \
	; mv docs.agent docs/artifacts \
	; mv docs.img docs/img