#!/usr/bin/env -S make -f
#
# hosted-partition.mk:
#   The hosted/seed partition, from a vanilla makefile that only `include`s
#   compose.mk.
#
#   Part of compose.mk is authored in CMK-lang, parked in an opaque `define
#   __hosted__`, lowered to a content-addressed cache and bound via GNU
#   make's makefile-remaking.  A plain `include compose.mk` (no supervisor,
#   no bash) transparently gets those targets: `hosted.selftest` below is
#   defined in CMK-lang inside the hosted region, yet callable here as an
#   ordinary target.  `tux.require`/`tux.purge` live there too (they need
#   docker, so they are not exercised by this demo).
#
#   On a cold cache, make builds it + restarts once; warm runs are a hash +
#   `-include`.
#
# USAGE:
#   ./demos/hosted-partition.mk           # run hosted target, vanilla make
#   ./demos/hosted-partition.mk selftest  # same, explicit

include compose.mk

__main__: hosted.selftest

selftest: hosted.selftest
