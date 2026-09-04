#!/usr/bin/env -S make -f
#
# elixir-1.mk:
#   Polyglots using elixir (the raw-make twin of elixir-1.cmk).  A code-object
#   is created from a `define` and bound to a container; running the target runs
#   the define's body in the image.  (Supersedes the older `docker.bind.script`.)
#
# USAGE: ./demos/elixir-1.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
elixir.img=elixir:otp-27-alpine
elixir.interpreter=elixir

# Now define the elixir code.
define hello_world.ex
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef

# Create a code-object from the define, bound to the elixir container.
$(call code, def=hello_world.ex img=${elixir.img} entrypoint=${elixir.interpreter})

__main__: hello_world.ex
