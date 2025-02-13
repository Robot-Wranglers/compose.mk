##
# TUI test suite for compose.mk 
#
# USAGE: ( from project root )
#
#   $ make tui-test
##
SHELL := bash
MAKEFLAGS=-sS --warn-undefined-variables
.SHELLFLAGS := -eu -c
.DEFAULT_GOAL := all 
include compose.mk


all:  tux.require test 

test: \
	test.docker.commander test.k3d.commander test.tux.commander \
	test.tux.demo

test.docker.commander:
	./compose.mk flux.apply.later/10/tux.panic docker.commander || true
test.k3d.commander:; ./compose.mk flux.apply.later/10/tux.panic k3d.commander || true
test.tux.demo:; ./compose.mk flux.apply.later/8/tux.panic tux.demo || true
test.tux.commander:; ./compose.mk tux.commander/flux.apply/io.wait/2,.tux.quit || true


# ./compose.mk flux.apply.later/8/tux.panic docker.commander || true
# make tux.mux/flux.timeout/2/io.bash,flux.timeout/2/io.bash
