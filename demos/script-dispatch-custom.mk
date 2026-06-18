#!/usr/bin/env -S make -f
# script-dispatch-custom.mk:
#   Container-agnostic script dispatch using a local, embedded Dockerfile.
#   The target script always runs from the container, but does not care whether
#   it's called from the host, or inside the container.
#
# USAGE: ./demos/script-dispatch-custom.mk

include compose.mk
__main__: my_script script_wrapper

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
