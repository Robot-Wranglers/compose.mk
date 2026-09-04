#!/usr/bin/env -S make -f
#
# script-dispatch-stock.mk:
#   Idioms for container-agnostic script dispatch with stock images.  A `define`
#   is bound to a container as a code-object; running the target runs the script
#   from inside the image, whether it's called from the host or the container.
#
# USAGE: ./demos/script-dispatch-stock.mk

include compose.mk

img=debian/buildd:bookworm

# The script to run in the container.
define script.sh
echo hello `hostname` at `uname -a`
endef

# A code-object named for the script define (target name == script name).
$(call code, def=script.sh img=${img} entrypoint=bash)

# If target and script name should differ, provide `namespace=`.
$(call code, def=script.sh namespace=wrapper_script img=${img} entrypoint=bash)

__main__: script.sh wrapper_script
