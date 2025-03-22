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
.DEFAULT_GOAL:=help

.SUFFIXES:
.PHONY: docs demos README.md

export SRC_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)
export PROJECT_ROOT := $(shell dirname ${THIS_MAKEFILE})

include compose.mk
$(eval $(call compose.import.generic,  _,  TRUE, demos/data/docker-compose.yml))

## BEGIN: Top-level
##
all: init clean build test docs

init: mk.stat docker.stat

clean: flux.stage.clean
	@# Only used during development; normal usage involves build-on-demand.
	@# Cache-busting & removes temporary files used by build / tests 
	rm -f tests/compose.mk
	find . | grep .tmp | xargs rm 2>/dev/null|| true

build normalize: # NOP

test: integration-test tui-test demo-test smoke-test 

smoke-test stest:
	ls tests/*.sh | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"

demos demos.test demo-test test.demos:
	set -x && ls demos/*mk | xargs -I% ${io.shell.isolated} sh -x -c "./% || exit 255"
bonk:
	ls demos/container-dispatch.mk | xargs -I% ${io.shell.isolated} sh -x -c "trace=1 ./%||exit 255"
ttest/%:; make test-suite/tui/${*}

itest integration-test: make -f demos/itest.mk

## BEGIN: Documentation related targets
##
define docs.builder.composefile
services:
  docs.builder: &base
    hostname: docs-builder
    build:
      context: .
      dockerfile_inline: |
        FROM python:3.9.21-bookworm
        RUN pip3 install --break-system-packages pynchon==2025.3.20.17.28 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2
        RUN apt-get update && apt-get install -y tree jq
    entrypoint: bash
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
  mmd:
    # <<: *base 
    hostname: mmd
    # interactive: true
    build:
      context: .
      dockerfile_inline: |
        FROM ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:10.6.1
        USER root 
        RUN apk add -q --update --no-cache coreutils alpine-sdk bash procps-ng
    working_dir: /workspace 
    volumes:
        - ${PWD}:/workspace
endef 
$(eval $(call compose.import.string,  docs.builder.composefile,  TRUE))
demo:
	@# Interactive selector for which demo to run.
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

docs: docs.jinja #docs.mermaid
docs.build: docs.builder.build docs.builder.dispatch/.mkdocs.build
docs.init:; pynchon --version
docs.jinja:
	@# Render all docs with jinja
	find docs | grep .j2 | sort  | grep -v macros.j2 \
	| xargs -I% sh -x -c "make docs.jinja/% || exit 255"
docs.jinja/% j/% jinja/%: docs.init
	@# Render the named docs twice (once to use includes, then to get the ToC)
	case ${*} in \
		*.md.j2) ${make} .docs.jinja/${*};; \
		*.md) ${make} .docs.jinja/${*}.j2;; \
		*) ${make} .docs.jinja/${*}.md.j2;; \
	esac
.docs.jinja/%:
	ls ${*} ${stream.obliviate} || ($(call log,${red} no such file ${*}); exit 39)
	$(call io.mktemp) && first=$${tmpf} \
	&& set -x && pynchon jinja render ${*} -o $${tmpf} --print \
	&& dest="`dirname ${*}`/`basename -s .j2 ${*}`" \
	&& mv $${tmpf} $${dest}


mmd.args=--theme neutral -b transparent
docs.mermaid docs.mmd:
	@# Renders all diagrams for use with the documentation 
	# pynchon mermaid apply
	find docs | grep '[.]mmd$$' | ${stream.peek} | ${flux.each}/.mmd.render
.mmd.render/%:
	output=`dirname ${*}`/`basename -s.mmd ${*}`.png \
	&& cmd="-i ${*} -o $${output} ${mmd.args}" ${make} mmd \
	&& cat $${output} | ${stream.img}


mkdocs: mkdocs.build mkdocs.serve
mkdocs.build build.mkdocs:; mkdocs build
.mkdocs.build:
	set -x && (make docs && mkdocs build --clean --verbose && tree site) \
	; find site docs|xargs chmod o+rw; ls site/index.html
mkdocs.serve serve:; mkdocs serve --dev-addr 0.0.0.0:8000

README.md:
	set -x && pynchon jinja render README.md.j2 -o README.md

## BEGIN: CI/CD related targets
##
actions.docs: docs.build 
	@# Entrypoint for docs-action
actions.lint:; cmd='-color' ${make} docker.image.run/rhysd/actionlint:latest 
	@# Helper for linting all action-yaml

actions.demos:
	@# Entrypoint for test-action
	${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"

actions.clean cicd.clean clean.github.actions:
	@# Cleans all action-runs that are cancelled or failed
	@#
	${make} actions.list/failure actions.list/cancelled \
	| ${stream.peek} | ${jq} -r '.[].databaseId' \
	| ${make} flux.each/actions.run.delete

actions.clean.img.test:
	gh run list --workflow=img-test.yml --json databaseId,createdAt \
	| jq '.[] | select(.createdAt | fromdateiso8601 < now - (60*60*10)) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.clean.old:
	gh run list --limit 1000 --json databaseId,createdAt \
	| jq '.[] | select(.createdAt | fromdateiso8601 < now - (60*60*24*7)) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.run.delete/%:; gh run delete ${*}
	@# Helper for deleting an action

actions.list/%:; gh run list --status ${*} --json databaseId
	@# Helper for filtering action runs
