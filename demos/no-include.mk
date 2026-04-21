#!/usr/bin/env -S make -f
#
# no-include.mk:
#   A very basic demo that *doesnt* include compose.mk.
#   This is mostly used for testing parsing & reflection utilities,etc
#
.DEFAULT_GOAL := __main__ 

__main__: clean build test

clean:
	@# Just a fake clean target. 
	echo cleaning 

build: 
	@# Just a fake build target.
	echo building

test:
	@# Just a fake test target. 
	echo testing