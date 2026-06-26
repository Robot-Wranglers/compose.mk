# plain.mk
#
# example plain-make PLUGIN.  Its name ends in `.mk`, so include.plugin
# binds it via a verbatim, copy-free `include` with no compile, no
# staging.  See also ./hello.cmk, which is JIT-compiled.
plugin.plain:
	$(call log.target, plain make plugin -- fast verbatim include)
