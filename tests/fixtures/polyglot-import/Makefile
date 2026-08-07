# Integration fixture: a code-object (img + entrypoint, no bind) mints a <namespace>.machine (defaults to the def name)
# (a plain cmk.machine) and binds the code-object to it; running the code-object runs its
# body inside the image.
include compose.mk

define mycode
whoami
endef

$(call code, def=mycode namespace=myp img=alpine:3.21.2 entrypoint=sh)
