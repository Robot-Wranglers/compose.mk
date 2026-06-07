# Integration fixture: polyglot.import (no bind) scaffolds an interpreter
# container. With a plain image + entrypoint=none, <ns>.interpreter/<cmd> runs
# <cmd> directly. Covers the <ns>.interpreter / <ns>.interpreter.base templates.
include compose.mk

define mycode
echo POLYGLOT-OK
endef

$(call polyglot.import, def=mycode namespace=myp img=alpine:3.21.2 entrypoint=none)
