#!/usr/bin/env -S make -f
#
# code-objects-2.mk: a python code-object created by one container, namespaced, with selected host env proxied in.
#
# USAGE: ./demos/code-objects-2.mk

include compose.mk

# Constants to share with the polyglot subprocess.
export planet=earth
export index=616

# py311: a pinned python container (entrypoint=python).
define py311
img=python:3.11-slim-bookworm entrypoint=python
endef
$(call cmk.container, def=py311)

# optimized: run a file with python -O -B in py311 (the customized interpreter invocation) -- the
# code-object binds to THIS target (not py311 directly), so it never re-enters py311's dispatch.
optimized/%:; $(call py311.__call__,-O -B ${*})

define hello_world.py
import os
print(f'hello {os.environ["planet"]} {os.environ["index"]}')
endef

# py311 creates the code-object (currying its img/runner); namespace= imports it as WORLD (so
# WORLD / WORLD.preview), and env= proxies just planet+index into the container.
$(call py311.polyglot, def=hello_world.py namespace=WORLD env='planet index')

# Preview the code (syntax-highlighted), then run it in the bound interpreter.
__main__: WORLD.preview WORLD
