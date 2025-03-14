#!/usr/bin/env -S make -f
# demos/uv.mk: 
#   Demonstrate polyglots with compose.mk.  
#   Python code running in a container, with dependencies and no venv, using uv. 
#   No caching! Note that this implicitly pulls not only dependencies but even 
#   the python version is also lazy and built just in time, immediately prior to use.
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/uv.mk

include compose.mk
.DEFAULT_GOAL := demo.uv

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
r = requests.get('https://httpbin.org/basic-auth/user/pass', auth=('user', 'pass'))
print(r.status_code)
endef

## Now run the code in the container, classic style invocation.
demo.uv:
	img=${uv.img} \
	entrypoint=${uv.interpreter} \
	cmd="run --script" \
	def=uv.hello_world \
	${make} docker.run.def

## More idiomatic approach: using target partials
demo.uv.alt: uv.script/uv.hello_world

uv.script/%:; set -a; cmd="run --script"; ${mk.def.read}/${*} | ${make} uv

uv:; ${stream.to.docker}/${uv.img},${uv.interpreter}
