#!/usr/bin/env -S make -f
# demos/etl-json.mk: 
#   Described a JSON-backed ETL pipeline with `compose.mk`
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/etl-json.mk

# Squash the default noisy output, include compose.mk primitives
.DEFAULT_GOAL := etl.safe
include compose.mk

# Declare an ETL pipeline, using `flux.pipeline` to bind tasks together.
# Roughly equivalent to => `make extract | make transform | make load`
etl: flux.pipeline/extract,transform,load

# Declare a "safe" version of the pipeline that handles failure/cleanup
etl.safe: flux.try.except.finally/etl,etl.failed,etl.cleanup

# Simulate individual tasks for extract/transform/load.  
# For convenience we ignore input and emit new JSON using the `jb` tool.
extract: 
	${jb} stage=extracted
transform: 
	${jb} stage=transformed
load:
	${jb} stage=loaded

# Simulate ETL handlers for failure and cleanup
etl.failed:
	$(call log, ETL failed!)
etl.cleanup:
	$(call log, Cleaning up ETL!)
