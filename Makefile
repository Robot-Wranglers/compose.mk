#!/usr/bin/env -S make -s -S -f 
##
# Project Automation
#
# Typical usage: `make clean build test`
#
# https://clarkgrubb.com/makefile-style-guide
# https://gist.github.com/rueycheng/42e355d1480fd7a33ee81c866c7fdf78
# https://www.gnu.org/software/make/manual/html_node/Quick-Reference.html
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
	ls tests/*.sh | xargs -I% -n1 script -q -e -c "env -i PATH=$${PATH} HOME=$${HOME} bash -x %||exit 255"

demos demos.test demo-test test.demos:
	ls demos/*mk | xargs -I% -n1 script -q -e -c "env -i PATH=$${PATH} HOME=$${HOME} bash -x -c \"make -f %\"||exit 255"

ttest/%:; make test-suite/tui/${*}
tui-test:
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
        RUN pip3 install --break-system-packages pynchon==2024.7.20.14.38 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2
        RUN apt-get update && apt-get install -y tree jq
    entrypoint: bash
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
endef 
$(eval $(call compose.import.string,  docs.builder.composefile,  TRUE))

.mkdocs.build:; set -x && (make docs && mkdocs build --clean --verbose && tree site) ; find site docs|xargs chmod o+rw; ls site/index.html
docs.build: docs.builder.build docs.builder.dispatch/.mkdocs.build
mkdocs: mkdocs.build mkdocs.serve
mkdocs.build build.mkdocs:; mkdocs build
mkdocs.serve serve:; mkdocs serve --dev-addr 0.0.0.0:8000

docs: README.md docs.jinja #docs.mermaid
README.md:
	set -x && pynchon jinja render README.md.j2 -o README.md
docs.jinja:
	@# Render all docs with jinja
	find docs | grep .j2 | sort  | grep -v macros.j2 \
	| xargs -I% sh -x -c "make docs.jinja/% || exit 255"

docs.init:; pynchon --version 

j/% jinja/% docs.jinja/%: docs.init
	@# Render the named docs twice (once to use includes, then to get the ToC)
	$(call io.mktemp) && first=$${tmpf} \
	&& set -x && pynchon jinja render ${*} -o $${tmpf} --print \
	&& dest="`dirname ${*}`/`basename -s .j2 ${*}`" \
	&& mv $${tmpf} $${dest}

docs.mermaid docs.mmd:
	@# Renders all diagrams for use with the documentation 
	pynchon mermaid apply

## BEGIN: CI/CD related targets
##
actions.docs: docs.build 
actions.lint:; docker run --rm -v $$(pwd):/workspace --workdir /workspace rhysd/actionlint:latest -color
actions.notebook.pipeline:; ${io.shell.isolated} script -q -e -c "bash --noprofile --norc -eo pipefail -x -c './demos/notebooking.mk tux.require lab.pipeline'"
actions.demos:; script -q -e -c "bash --noprofile --norc -eo pipefail -x -c 'make demos'"
actions.clean cicd.clean: clean.github.actions
clean.github.actions:
	@#
	@#
	gh run list --status failure --json databaseId \
	| ${stream.peek} | jq -r '.[].databaseId' \
	| xargs -n1 -I% sh -x -c "gh run delete %"

demo:
	@#
	@#
	pattern='*.mk' dir=demos/ ${make} flux.select.file/mk.select

actions.lint:; docker run --rm -v $$(pwd):/workspace --workdir /workspace rhysd/actionlint:latest -color
