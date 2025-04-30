#!/usr/bin/env -S make -f
# demos/julia.mk: 
#   Demonstrating polyglots as first-class objects in `compose.mk`, and compiled languages via FFI
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/julia.mk

include compose.mk

# First we pick an image and interpreter for the language kernel.
julia.img=julia:1.10.9-alpine3.21
julia.interpreter=julia 

# Binds the docker image / entrypoint to a target, 
# then create a unary target for accepting a filename.
julia:; ${docker.image.run}/${julia.img},${julia.interpreter}
julia.interpreter/%:; ${docker.curry.command}/julia

# Next we define some Julia code that uses `ccall` for access to C.
define hello_world 
println("Hello world! (from Julia & C)")
using Printf
using Statistics  # For mean function
using Libdl       # For dlopen, dlsym, etc.

# Get current time using C's time() function
# In Julia container, we can use libc.so.6 or use C_NULL to make Julia find it
function get_system_time()
    return ccall(:time, Int64, (Ptr{Nothing},), C_NULL)
end

# Generate random numbers using rand() function and time as seed
function c_random_array(size::Int)
    ccall(:srand, Nothing, (UInt32,), UInt32(get_system_time()))
    result = Vector{Int}(undef, size)
    for i in 1:size
        result[i] = ccall(:rand, Int32, ())
    end
    return result
end

# Call C's math library for complex calculations
# Use dlopen to explicitly load libm.so.6, closing after use
function c_math_operations(x::Float64)
    libm = Libdl.dlopen("libm.so.6")
    sin_x = ccall(dlsym(libm, :sin), Float64, (Float64,), x)
    log_x = ccall(dlsym(libm, :log), Float64, (Float64,), x)
    sqrt_x = ccall(dlsym(libm, :sqrt), Float64, (Float64,), x)
    Libdl.dlclose(libm)
    return (sin=sin_x, log=log_x, sqrt=sqrt_x)
end

println("Julia C Library Integration Example\n==================================")

# Generate and analyze random numbers using C's rand
println("Random numbers from C's rand():")
rand_array = c_random_array(10)
println("  Sample: $rand_array")
println("  Mean=$(mean(rand_array)) Max=$(maximum(rand_array))")
println()

# Math operations using C's libm
x = 2.0
math_results = c_math_operations(x)
println("Math operations on x = $x:")
@printf "  sin(x) = %.6f\n" math_results.sin
@printf "  log(x) = %.6f\n" math_results.log
@printf "  sqrt(x) = %.6f\n" math_results.sqrt
endef

# Declare the above code-block as a first class object, and bind it to an interpreter.
$(eval $(call compose.import.code, hello_world, julia.interpreter))

# Use our new scaffolded targets for `preview` and `run`
__main__: hello_world.preview hello_world.run