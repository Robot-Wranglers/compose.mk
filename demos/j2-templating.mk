#!/usr/bin/env -S make -f
# Demonstrates templating in jinja.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/j2-templating.mk

include compose.mk

define Dockerfile.jinjanator
FROM python:3.11-slim-bookworm
RUN pip install jinjanator --break-system-packages
endef

define hello_template.j2
{% for i in range(3) %}
hello {{name}}! ( {{loop.index}} )
{% endfor %}
endef

define bye_template.j2
bye {{name}}!
endef

# An "interpreter" for templates.
# This renders the given template file using JSON on stdin.
render/%:
	cmd="--quiet -fjson ${*} /dev/stdin" \
		${make} mk.docker/jinjanator,jinjanate

# Import the template-block, binding the 
# interpreter & creating `*.j2` targets
$(call polyglots.import, pattern=[.]j2 bind=render)

# Generates JSON with `jb`, then pushes it into the template renderer.
# This shows how to call targets using generated symbols, 
# and then (equivalently) using explicit targets.
__main__: Dockerfile.build/jinjanator
	${jb} name=foo | ${hello_template.j2}
	${jb} name=foo | ${bye_template.j2}
	${jb} name=foo | ${make} bye_template.j2
