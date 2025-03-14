#!/usr/bin/env -S make -f
# demos/elixir.mk: 
#   Demonstrating polyglots using elixir.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#   See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   USAGE: ./demos/elixir.mk

include compose.mk
.DEFAULT_GOAL := demo.elixir

# First we pick an image and interpreter for the language kernel.
# Here, iex can work too, but there are minor differences.
elixir.img=elixir:otp-27-alpine
elixir.interpreter=elixir 

# Now define the elixir code
define hello_world 
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef

# Now show three equivalent ways to run the code inside the container
demo.elixir: demo.elixir1 demo.elixir2 demo.elixir3

# Classic style invocation, using simplest available helper
demo.elixir1:
	img=${elixir.img} entrypoint=${elixir.interpreter} \
		def=hello_world ${make} docker.run.def
	
# Arguably more idiomatic style, using macros & pipes
demo.elixir2:
	${mk.def.read}/hello_world \
		| ${stream.to.docker}/${elixir.img},${elixir.interpreter}

# Fully manual style, handling your own tmpfiles, and sticking to targets
demo.elixir3:
	${make} mk.def.read/hello_world > tmpf
	cmd=tmpf ${make} docker.image.run/${elixir.img},${elixir.interpreter}
	rm -f tmpf