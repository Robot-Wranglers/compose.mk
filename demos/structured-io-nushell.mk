#!/usr/bin/env -S make -f
# Demonstrates some nushell interoperability.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE: ./demos/structured-io-nushell.mk

include compose.mk

__main__: test.nushell_generic test.pattern_matching test.parse_cols

test.nushell_generic:
	$(call log.test, Pass stream + arbitrary commands to nushell)
	echo '{"foo":"bar"}' \
		| cmd='from json | to yaml' ${make} stream.nushell

test.nushell_pipe:
	$(call log.test, Passing stream and arbitrary commands to nushell)
	echo '{"foo":"bar"}' \
		| cmd='from json | to yaml' ${make} stream.nushell


test.nushell_pipeline:
	$(call log.test, Pass stream and arbitrary commands to nushell)
	echo '{"foo":"bar"}' \
		| ${make} stream.nushell/from_json,to_yaml

test.pattern_matching:
	$(call log.test, Pattern-matching and parsing line-oriented input)
	echo "libfoobar@2.5.3 -- A library for doing foobars" \
		| pattern='{lib}@{version} -- {description}' \
			${make} stream.parse.patterns

test.parse_cols:
	$(call log.test, Autodetect and parse column-oriented input)
	df -h \
		| ${make} stream.parse.cols \
		| ${jq} '.[-1]'