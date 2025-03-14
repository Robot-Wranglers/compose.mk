#!/usr/bin/env -S make -f
# demos/logging.mk: 
#   Shows some of the compose.mk logging facilities.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/logging.mk

include compose.mk
.DEFAULT_GOAL := all

# Runs all the examples 
all: logging_example.basic logging_example.formatting logging_example.json

# Basic example, just write a message to log.
logging_example.basic:
	$(call log, unquoted message that should go to log)

# Formatting example, using some of the available ANSI color constants.
logging_example.formatting:
	$(call log, ${red}unquoted message ${sep} ${no_ansi}that should ${dim} go to ${bold} log)

# Trace-logging example: this shows output only when the
# variables `trace` or `TRACE` are set to 1 in the environment
logging_example.trace:
	$(call log.trace, unquoted message that should go to log)

# JSON-logging: decodes input with `jb`, 
# then pretty-prints corresponding JSON to stderr.
# This is indented by default, but also expanded.  
# Use `log.json.min` for minified version.
logging_example.json:
	$(call log.json.min, stage=Building )
	$(call log.json, stage=Building more=info anything=you_want)
