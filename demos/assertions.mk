#!/usr/bin/env -S make -f
#
# assertions.mk: defensive precondition checks from compose.mk's assert.*
# namespace.
#
# Every assert.* shares one contract: pass quietly when the condition
# holds, fail loudly (a red log line + nonzero exit) when it doesn't -- so
# they drop in as recipe guards or as target prerequisites.  This demo
# exercises the passing path of each; the commented lines show the failing
# path (uncomment to watch one fail loudly).
#
# USAGE: ./demos/assertions.mk

include compose.mk

# Environment assertions -- a variable is set and non-empty.  Two forms
# (both shown):
#   assert.env/<V1>,<V2>:
#       the multi-var target (comma-separated); ideal as a prereq
#   $(call assert.env.var, <V>):
#       the single-variable primitive (macro), for inline guards
demo.env: assert.env/HOME,PATH
	@# (Related: argument-parsing treats any kwarg mentioned without a default
	@# as required.)
	$(call assert.env.var, HOME)
	$(call log, environment assertions passed)
	@# would fail loudly (exit 39): asserting env.var on an unset var like
	@# DEFINITELY_UNSET_XYZ

# Tool assertions -- a CLI tool is on PATH (a thin wrapper over which).
#   $(call assert.tool.required, <tool>[, <install-msg>]):
#       the macro form, for inline guards
#   assert.tool.required/<tool>:
#       the target form; great as a prereq
demo.tools: assert.tool.required/bash
	$(call assert.tool.required, make, Install GNU make and retry)
	$(call log, tool assertions passed)
	@# would fail loudly (exit 1): asserting tool.required on a missing tool like
	@# no_such_tool_xyz

# Stream assertions -- stdin is a real stream, not an interactive tty.  For
# targets/macros that must consume piped input.
#   $(call assert.stream.stdin.required):
#       the macro form (no target twin)
demo.stream:
	$(call assert.stream.stdin.required)
	${stream.stdin} | ${stream.as.log}

__main__:
	${make} demo.env
	${make} demo.tools
	@# demo.stream needs a stream, so feed it one (running it tty-less would
	@# fail loudly):
	echo 'piped input -> stream assertion passes' | ${make} demo.stream
