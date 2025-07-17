#!/usr/bin/env -S make -f
# Demonstrating idioms for container-agnostic script dispatch with stock images.
# The target script always runs from the container, but does not care whether 
# it's called from the host, or inside the container.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
#
# USAGE: ./demos/script-dispatch-stock.mk

include compose.mk

img=debian/buildd:bookworm

__main__: script.sh wrapper_script

# Create target from the implied script and the given image
script.sh:; $(call docker.bind.script, img=${img})
define script.sh
echo hello `hostname` at `uname -a`
endef

# If target and script name differ, provide 2nd argument
wrapper_script:; $(call docker.bind.script, img=${img} def=script.sh)
