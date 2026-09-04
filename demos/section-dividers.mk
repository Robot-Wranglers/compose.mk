#!/usr/bin/env -S make -f
#
# section-dividers.mk: Some of the compose.mk logging capabilities.
#
# USAGE: ./demos/section-dividers.mk clean build test

include compose.mk 

__main__: clean build test

clean: io.print.banner
	@# Use `io.print.banner` implicitly as a prereq => Timestamped divider
	echo Cleaning stuff

build: 
	@# Call `io.print.banner` explicitly => Full control over divider label
	label="Build Stage" ${make} io.print.banner
	echo Building stuff

test:
	@# Use `io.print.banner` as a macro => Automatically set label as the
	@# current target's name
	${io.print.banner}
	echo Testing stuff
	label="divider-using-gum" ${make} io.draw.banner
	label=test1 ${make} io.figlet
	label=test2 ${make} io.with.color/dim,io.figlet
	label=test3 ${make} io.with.color/cyan,io.figlet
	label=test4 ${make} io.with.color/red,io.figlet
