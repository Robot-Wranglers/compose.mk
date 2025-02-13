# demos/elixir.mk: 
#   Minimal demo for polyglotting Makefiles with foreign languages.  This uses elixir.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/elixir.mk

include compose.mk
.DEFAULT_GOAL := demo.elixir

# First we pick an image for the language kernel
export IMG_ELIXIR?=elixir:otp-27-alpine

# Now define the elixir code
define Elixir.hello_world 
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef

# Now run the code inside the container
demo.elixir:
	img=$${IMG_ELIXIR} \
	entrypoint=elixir \
	def=Elixir.hello_world \
	${make} docker.run.def

