#!/usr/bin/env -S make -f
# Demonstrating io.mktemp.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/standard-lib
# USAGE: ./demos/guests.mk

include compose.mk

__main__: flux.star/test

test.mktemp_var:
	@# Use `io.mktemp` to create a tempfile, 
	@# storing path details in `tmpf` var. This will 
	@# be removed when the process that created it exits, 
	@# so ensure process management with `&&` or `;` etc
	${io.mktemp} \
	&& $(call log.test, $${tmpf}) \
	&& ls $${tmpf} > /dev/null

test.mktempd_var:
	@# Use `io.mktempd` for a tempdir, 
	@# storing path details in `tmpd` var.
	${io.mktempd} \
	&& $(call log.test, $${tmpd}) \
	&& touch $${tmpd}/my-tmp-file \
	&& find $${tmpd} | ${stream.as.log}

test.mktemp_macro:
	@# Call _io.mktemp to use a given var instead of `tmpf`
	$(call _io.mktemp, var=derived) \
	&& $(call log.test, $${derived}) \
	&& ls $${derived} > /dev/null
	