# demos/no-include.mk: 
#   A demo that *doesnt* include compose.mk.  
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/no-include.mk

# NB: this boilerplate helps to quit the default output- 
# and you'll need this whenever you want to emit JSON.
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := no-op

no-op:

clean:
	@# Just a fake clean target. 
	echo cleaning 

# Just a fake `build` target 
build:; echo building 

# Just a fake `test` target.
test:; echo testinging 

# demo.let:
# 	./compose.mk \
# 		mk.include/demos/no-include.mk \
# 		mk.let/foo:flux.ok