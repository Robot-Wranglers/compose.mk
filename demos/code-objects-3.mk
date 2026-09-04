#!/usr/bin/env -S make -f
#
# code-objects-3.mk: python code-objects sharing one container -- bound to py311's `optimized`
#                    interpreter via the pattern= glob.
#
# USAGE: ./demos/code-objects-3.mk

include compose.mk

# py311: a pinned python container (entrypoint=python).
define py311
img=python:3.11-slim-bookworm entrypoint=python
endef
$(call cmk.container, def=py311)

# optimized: run a file with python -O -B in py311 (the customized interpreter invocation) -- the
# code-objects bind to THIS target (not py311 directly), so it never re-enters py311's dispatch.
optimized/%:; $(call py311.__call__,-O -B ${*})

define one.py
import sys
print([sys.platform, sys.argv])
endef

define two.py
import sys
print(f'hello world, from {sys.version_info}')
for i in range(3):
    print(f"  count{i}")
endef

# Bind every .py block to py311's optimized interpreter (glob), scaffolding a target per block.
$(call code.import, pattern=[.]py bind=optimized)

__main__: one.py two.py
