#!/usr/bin/env -S make -f
# demos/logging.mk: 
#   Shows some of the compose.mk logging facilities.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE: ./demos/logging.mk

include compose.mk

# Runs all the examples 
__main__: \
	logging_example.command logging_example.files \
	logging_example.basic logging_example.json \
	logging_example.formatting

logging_example.command:
	@# Send stdout for any command to the logging stream
	echo hello logging | ${stream.as.log}

logging_example.files:
	@# Since `io.preview.file` writes to stderr, this is technically logging
	${make} io.preview.file/demos/logging.mk
	$(call log.preview.file, demos/logging.mk)

logging_example.basic:
	@# Basic example, just write a message to log.
	$(call log, unquoted message that should go to log)
	$(call log.io, msg from io module)
	$(call log.flux, msg from flux module)
	$(call log.docker, msg from docker module)

logging_example.formatting:
	@# Formatting example, using some of the available ANSI color constants.
	$(call log, ${red}unquoted message ${sep} \
		${no_ansi}that should ${dim}go to ${bold}log)

logging_example.trace:
	@# Trace-logging example: this shows output only when the
	@# variables `trace` or `TRACE` are set to 1 in the environment
	$(call log.trace, unquoted message that should go to log)

logging_example.json:
	@# JSON-logging: decodes input with `jb`, 
	@# then pretty-prints corresponding JSON to stderr.
	@# This is indented by default, but also expanded.  
	@# Use `log.json.min` for minified version.
	$(call log.json.min, stage=Building)
	$(call log.json, stage=Building more=info anything=you_want)

