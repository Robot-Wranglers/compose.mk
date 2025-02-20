# demos/logging.mk: 
#   Shows some of the logging capabilities with make-functions.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/section-dividers.mk clean build test

include compose.mk 

.DEFAULT_GOAL := all 

all: clean build test

# use `io.print.div` implicitly as a prereq => Timestamped divider
clean: io.print.div
	echo Cleaning stuff

# call `io.print.div` explicitly => Full control over divider label
build: 
	label="Build Stage" ${make} io.print.div
	echo Building stuff

# use `io.print.div` as a macro => Automatically set label as the current target's name
test:
	${io.print.div}
	echo Testing stuff
	label="divider using gum" ${make} io.gum.style
	