#!/usr/bin/env -S make -f
#
# io.mktemp.mk:
#   Scratch files & directories with the `io.mktemp` family.  Each helper
#   exports a shell var holding the path AND registers an EXIT trap that
#   removes it, so a temp lives only as long as the process that created
#   it.  Keep the whole recipe in one shell (chain with `&&`/`;`) so the
#   var and its trap stay in scope.
#
# USAGE: ./demos/io.mktemp.mk

include compose.mk

__main__: demo.tempfile demo.tempdir demo.custom_var

demo.tempfile:
	@# `io.mktemp` exports `tmpf`: a fresh ./.tmp.* file, auto-removed on
	@# exit.
	${io.mktemp} \
	&& $(call log.io, io.mktemp ${sep} made a tempfile at $${tmpf}) \
	&& printf 'scratch data\n' > $${tmpf} \
	&& cat $${tmpf}

demo.tempdir:
	@# `io.mktempd` exports `tmpd`: a fresh ./.tmp.* directory (also
	@# auto-removed).
	${io.mktempd} \
	&& $(call log.io, io.mktempd ${sep} made a tempdir at $${tmpd}) \
	&& touch $${tmpd}/a $${tmpd}/b \
	&& find $${tmpd} | ${stream.as.log}

demo.custom_var:
	@# `_io.mktemp` takes a `var=` so the path lands in a name you pick (here
	@# `work`) instead of the default `tmpf` -- handy when juggling several
	@# at once.
	$(call _io.mktemp, var=work) \
	&& $(call log.io, _io.mktemp ${sep} made a tempfile in a custom var $${work}) \
	&& printf 'hi\n' > $${work} \
	&& cat $${work}
