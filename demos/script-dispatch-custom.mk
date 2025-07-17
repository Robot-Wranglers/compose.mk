#!/usr/bin/env -S make -f
# Demonstrating idioms for container-agnostic script dispatch with stock images.
# The target script always runs from the container, but does not care whether 
# it's called from the host, or inside the container.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
#
# USAGE: ./demos/script-dispatch-custom.mk

include compose.mk
__main__: my_script 

# Look, it's a container definition 
define Dockerfile.my_container
FROM debian/buildd:bookworm
# .. Other customization here .. 
endef

# Look, it's a script to run in the container 
define my_script
echo hello `hostname` at `uname -a`
endef

# Binds the given target to the given container + implied script
my_script:; $(call mk.docker.bind.script, img=my_container)

# If script and target names differ, provide `def` argument
script_wrapper:; $(call mk.docker.bind.script, img=my_container def=my_script)
