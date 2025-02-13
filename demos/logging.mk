# demos/logging.mk: 
#   Shows some of the logging capabilities with make-functions.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/logging.mk

# Squash the default noisy output, then override 
# the default goal and include compose.mk primitives
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := all
include compose.mk

# Runs all the examples 
all: logging_example.basic logging_example.formatting logging_example.json

# Basic example, just write a message to log.
logging_example.basic:
	$(call log, unquoted message that should go to log)

# Formatting example, using some of the available ANSI color constants.
logging_example.formatting:
	$(call log, ${red}unquoted message ${sep} ${no_ansi}that should ${dim} go to ${bold} log)

# Trace-logging" example," this only shows if `trace` or `TRACE` is set to 1 in the environment
logging_example.trace:
	$(call log.trace, unquoted message that should go to log)

# JSON-logging: decodes input with `jb`, then pretty-prints corresponding JSON to stderr.
# This is indented by default, but expanded by default.  Use `log.json.min` for minified version.
logging_example.json:
	$(call log.json.min, stage=Building )
	$(call log.json, stage=Building more=info anything=you_want)


