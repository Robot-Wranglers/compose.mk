#!/usr/bin/env -S make -f
# julia.mk: ccall FFI into C; twin of cmk/julia.cmk.

include compose.mk

# image + interpreter for the language kernel
julia.img=julia:1.10.9-alpine3.21
julia.interpreter=julia

# bind the image to a target + a unary filename target
julia:; ${docker.image.run}/${julia.img},${julia.interpreter}
julia.interpreter/%:; ${docker.curry.command}/julia

define hello_world
println("Hello world! (from Julia & C)")
n = ccall(:rand, Int32, ())
println("a random int from C's rand() = $n")
endef

# declare the block as a code object bound to the interpreter
$(call code, def=hello_world bind=julia.interpreter)

__main__: hello_world hello_world.preview
