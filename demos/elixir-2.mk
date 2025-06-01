#!/usr/bin/env -S make -f
# Demonstrating polyglots using elixir (low-level helpers)
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/elixir-1.mk

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

__main__: alt1 alt2 alt3
 
# Now show three equivalent ways to run the code inside the container
alt1:
	@# Classic style invocation, using simplest available helper
	img=${elixir.img} entrypoint=${elixir.interpreter} \
		def=hello_world ${make} docker.run.def

alt2:
	@# Another way, using piping and streams
	${mk.def.read}/hello_world \
		| ${stream.to.docker}/${elixir}

alt3:
	@# Fully manual style, handling your own temp files,
	@# and sticking to targets instead of using pipes
	${mk.def.to.file}/hello_world/temp-file
	cmd=temp-file ${make} docker.image.run/${elixir}
	rm -f temp-file