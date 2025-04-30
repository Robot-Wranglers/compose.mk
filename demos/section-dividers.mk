#!/usr/bin/env -S make -f
# demos/section-dividers.mk: 
#   Shows some of the compose.mk logging capabilities.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
#   USAGE: ./demos/section-dividers.mk clean build test

include compose.mk 

__main__: clean build test

# Use `io.print.banner` implicitly as a prereq => Timestamped divider
clean: io.print.banner
	echo Cleaning stuff

# Call `io.print.banner` explicitly => Full control over divider label
build: 
	label="Build Stage" ${make} io.print.banner
	echo Building stuff

# Use `io.print.banner` as a macro => Automatically set label as the current target's name
test:
	${io.print.banner}
	echo Testing stuff
	label="divider-using-gum" ${make} io.draw.banner
	label=test1 ${make} io.figlet
	label=test2 ${make} io.with.color/dim,io.figlet
	label=test3 ${make} io.with.color/cyan,io.figlet
	label=test4 ${make} io.with.color/red,io.figlet
