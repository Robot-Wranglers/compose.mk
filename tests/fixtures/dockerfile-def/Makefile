# Integration fixture: a project Makefile that includes compose.mk and supplies
# an embedded Dockerfile via a define-block, for the Dockerfile.build path.
# The `project` fixture copies compose.mk into the project dir, so the natural
# `include compose.mk` resolves.
include compose.mk

define Dockerfile.app
FROM alpine:3.21.2
endef
