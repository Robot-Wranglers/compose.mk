#!/usr/bin/env -S make -f
# Demonstrating polyglots using elixir
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/elixir-1.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
elixir.img=elixir:otp-27-alpine
elixir.interpreter=elixir 

# Now define the elixir code
define hello_world.ex
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef

__main__: hello_world hello_world.ex

# A decorator-style idiom:
# Name the target, then get the target-body from spec.
hello_world:; \
	$(call docker.bind.script, \
		def=hello_world.ex img="${elixir.img}" \
		entrypoint=${elixir.interpreter})

# Alternate: Omit `def` argument if the target 
# name matches the name of the code-block.
hello_world.ex:; \
	$(call docker.bind.script, \
		img=${elixir.img} entrypoint=${elixir.interpreter})