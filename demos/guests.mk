#!/usr/bin/env -S make -f
# Demonstrating "special guest" polyglots in awk/bash.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/guests.mk

include compose.mk

__main__: flux.star/test. #test.awker test.basher.args #test.basher.stdin 

define echo.awk
{print $0}
endef
test.awker:
	$(call log.test, Run the embedded awk script on stdin)
	echo foo bar | ${make} io.awker/echo.awk | grep "foo bar"

define echo.sh
cat /dev/stdin
endef
test.basher.stdin:
	$(call log.test, Run the embedded bash script on stdin)
	echo foo bar | ${make} io.basher/echo.sh | grep "foo bar"

define tmp.sh
echo hello ${1} ${2}
endef
test.basher.args:
	$(call log.test, Run the embedded bash with arguments)
	${make} io.basher/tmp.sh,foo,bar | grep "foo bar"

define broken.sh
exit 1
endef
test.broken:
	$(call log.test, Check exit status for broken script)
	! ${make} io.basher/broken.sh