#!/usr/bin/env -S make -f
# Demonstrating "special guest" polyglots in awk/bash.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: 
#   * http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   * demos/script-dispatch-host.mk
# USAGE: ./demos/guests.mk

include compose.mk

# Runs all of the test.* targets 
__main__: flux.timer/flux.star/test.

define echo.awk
{print $0}
endef
test.io.awk:
	$(call log.test, Run the embedded awk script on stdin)
	echo foo bar | ${io.awk}/echo.awk | grep "foo bar"

define echo.sh
cat /dev/stdin
endef
test.io.bash.stdin:
	$(call log.test, Run the embedded bash script on stdin)
	echo foo bar | ${io.bash}/echo.sh | grep "foo bar"

define tmp.sh
echo hello ${1} ${2}
endef
test.io.bash.args:
	$(call log.test, Run the embedded bash with arguments)
	${io.bash}/tmp.sh,foo,bar | grep "foo bar"

define broken.sh
exit 1
endef
test.io.bash.broken:
	$(call log.test, Check exit status for broken script)
	! ${io.bash}/broken.sh