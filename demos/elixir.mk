#!/usr/bin/env -S make -f
# demos/elixir.mk: 
#   Demonstrating polyglots using elixir.
#   Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#   See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   USAGE: ./demos/elixir.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
# Here, iex can work too, but there are minor differences.
elixir.img=elixir:otp-27-alpine
elixir.interpreter=elixir 
elixir=${elixir.img},${elixir.interpreter}

# Now define the elixir code
define hello_world 
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef

# Now show three equivalent ways to run the code inside the container
__main__: demo.elixir1 demo.elixir2 demo.elixir3

# Classic style invocation, using simplest available helper
demo.elixir1:
	img=${elixir.img} entrypoint=${elixir.interpreter} \
		def=hello_world ${make} docker.run.def
	
# Another way, using piping and streamsmacros & pipes
demo.elixir2:
	${mk.def.read}/hello_world \
		| ${stream.to.docker}/${elixir}

# Fully manual style, handling your own tmpfiles, and sticking to targets
demo.elixir3:
	${mk.def.to.file}/hello_world/temp-file
	cmd=temp-file ${make} docker.image.run/${elixir}
	rm -f temp-file