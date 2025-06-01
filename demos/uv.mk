#!/usr/bin/env -S make -f
# Demonstrate polyglots with compose.mk.  Python code running in a container, 
# with dependencies and no venv, using uv. No caching! Note that this implicitly 
# pulls not only dependencies but the python version itself is lazy and built 
# just in time.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
# USAGE: ./demos/uv.mk

include compose.mk

# Pick an image and a interpreter for the language kernel
# https://docs.astral.sh/uv/guides/integration/docker/
uv.img=ghcr.io/astral-sh/uv:debian
uv.interpreter=uv

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
r = requests.get(
  'https://httpbin.org/basic-auth/user/pass', 
  auth=('user', 'pass'))
print(r.status_code)
endef

# Run the code in the container, using low-level helpers.
__main__:
	img=${uv.img} \
	entrypoint=${uv.interpreter} \
	cmd="run --script" \
	def=uv.hello_world \
	${make} docker.run.def
