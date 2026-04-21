#!/usr/bin/env -S make -f
#
# logging.mk: Some of the compose.mk logging facilities.
#
# USAGE: ./demos/logging.mk

include compose.mk

# Runs all the examples 
__main__: \
	demo.command demo.files \
	demo.basic demo.json \
	demo.formatting

demo.command:
	@# Send stdout for any command to the logging stream
	echo hello logging | ${stream.as.log}

demo.files:
	@# Since `io.preview.file` writes to stderr, this is technically logging
	${make} io.preview.file/demos/logging.mk
	$(call log.preview.file, demos/logging.mk)

demo.basic:
	@# Basic example, just write a message to log.
	$(call log.base, unquoted message that should go to log)
	$(call log.io, msg from io module)
	$(call log.flux, msg from flux module)
	$(call log.docker, msg from docker module)

demo.formatting:
	@# Formatting example, using some of the available ANSI color constants.
	$(call log.base, ${red}unquoted message ${sep} \
		${no_ansi}that should ${dim}go to ${bold}log)

demo.trace:
	@# Trace-logging example: this shows output only when the
	@# variables `trace` or `TRACE` are set to 1 in the environment
	$(call log.trace, unquoted message that should go to log)

demo.json:
	@# JSON-logging: decodes input with `jb`, 
	@# then pretty-prints corresponding JSON to stderr.
	@# This is indented by default, but also expanded.  
	@# Use `log.json.min` for minified version.
	$(call log.json.min, stage=Building)
	$(call log.json, stage=Building more=info anything=you_want)

