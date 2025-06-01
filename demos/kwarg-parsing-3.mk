#!/usr/bin/env -S make -f
# Demonstrating using `mk.unpack.kwargs`. 
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/kwarg-parsing-3.mk

include compose.mk

# Define `target_factory`, which builds new targets on demand.
# Supports keyword-arg style input using `mk.unpack.kwargs`,
# where `shape` is required, and `color` is optional
target_factory=$(eval $(call target_factory.src, ${1}))
define target_factory.src
$(call mk.unpack.kwargs, ${1}, shape)
$(call mk.unpack.kwargs, ${1}, color, default)
$(call mk.unpack.kwargs, ${1}, quoted, default data)
${kwargs_shape}:
	echo "A ${kwargs_color} ${kwargs_shape} /${kwargs_quoted}/"
endef

# Create targets for several shapes
$(call target_factory, shape=triangle)
$(call target_factory, shape=square color=black)
$(call target_factory, shape=circle color=yellow quoted='single quotes only')

# Exercise the dynamically generated targets 
__main__: triangle circle square
