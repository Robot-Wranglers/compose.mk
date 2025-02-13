# demos/uv.mk: 
#   Python code running in a container, with dependencies and no venv, using uv. No caching! 
#   Note that this implicitly pulls not only dependencies but the python version is also lazy.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/elixir.mk

include compose.mk
.DEFAULT_GOAL := demo.uv

# First we pick an image for the language kernel
# https://docs.astral.sh/uv/guides/integration/docker/
export IMG_UV?=ghcr.io/astral-sh/uv:debian

# Now define the script and dependencies
define uv.hello_world 
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "requests==2.31.0",
# ]
# ///
import requests
r = requests.get('https://httpbin.org/basic-auth/user/pass', auth=('user', 'pass'))
print(r.status_code)
endef

# Now run the code inside the container
demo.uv:
	img=$${IMG_UV} def=uv.hello_world \
	entrypoint=uv cmd="run --script" \
	${make} docker.run.def

