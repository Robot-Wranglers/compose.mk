# demos/no-include.mk: 
#   A very basic demo that *doesnt* include compose.mk.  
#   This is mostly used for testing parsing and reflection utilities
.DEFAULT_GOAL := all 

all: clean build test

clean:
	@# Just a fake clean target. 
	echo cleaning 

# Just a fake `build` target 
build:; echo building 

# Just a fake `test` target.
test:
	echo testing