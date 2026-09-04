#!/usr/bin/env -S make -f
#
# script-dispatch-custom.mk:
#   Container-agnostic script dispatch using a local, embedded Dockerfile.  The
#   image is built from an inline `Dockerfile.<name>` define (via the
#   `Dockerfile.build/<name>` prereq), then a code-object bound to that image
#   runs the script inside it.
#
# USAGE: ./demos/script-dispatch-custom.mk

include compose.mk

# Look, it's a container definition.
define Dockerfile.my_container
FROM debian/buildd:bookworm
# .. Other customization here ..
endef

# Look, it's a script to run in the container.
define my_script
echo hello `hostname` at `uname -a`
endef

# Code-objects bound to the locally-built image.
$(call code, def=my_script img=compose.mk:my_container entrypoint=bash)
$(call code, def=my_script namespace=script_wrapper img=compose.mk:my_container entrypoint=bash)

# Build the image (prereq), then run the scripts in it.
__main__: Dockerfile.build/my_container my_script script_wrapper
