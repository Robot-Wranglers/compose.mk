#!/usr/bin/env -S make -f
#
# guests.mk: "Special guest" polyglots in awk/bash.
#
#   See also: 
#   * http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   * demos/host-native-bash.mk
# USAGE: ./demos/guests.mk

include compose.mk

# Runs all of the test.* targets 
__main__: flux.timer/flux.star/test.

define echo.awk
{print $0}
endef
test.io.awk:
	$(call log.test, Run the embedded awk script on stdin)
	echo foo bar | ${io.awk}/echo.awk

define echo.sh
cat /dev/stdin
endef
test.io.bash.stdin:
	$(call log.test, Run the embedded bash script on stdin)
	echo foo bar | ${io.bash}/echo.sh

define tmp.sh
echo hello ${1} ${2}
endef
test.io.bash.args:
	$(call log.test, Run the embedded bash with arguments)
	${io.bash}/tmp.sh,foo,bar