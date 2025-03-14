#!/usr/bin/env -S make -f
# demos/section-dividers.mk: 
#   Shows some of the compose.mk logging capabilities.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: ./demos/section-dividers.mk clean build test

include compose.mk 

.DEFAULT_GOAL := __main__ 

__main__: clean build test

# Use `io.print.div` implicitly as a prereq => Timestamped divider
clean: io.print.div
	echo Cleaning stuff

# Call `io.print.div` explicitly => Full control over divider label
build: 
	label="Build Stage" ${make} io.print.div
	echo Building stuff

# Use `io.print.div` as a macro => Automatically set label as the current target's name
test:
	${io.print.div}
	echo Testing stuff
	label="divider-using-gum" ${make} io.draw.banner
	label=test1 ${make} io.figlet
	label=test2 ${make} io.with.color/dim,io.figlet
	label=test3 ${make} io.with.color/cyan,io.figlet
	label=test4 ${make} io.with.color/red,io.figlet
