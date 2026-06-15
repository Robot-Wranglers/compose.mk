# Integration fixture: docker.import (with def=) scaffolds run/dispatch/clean
# targets for an inline Dockerfile def. make+bash are installed so dispatch works,
# and the base is native-arch so direct `run` of a command works too.
include compose.mk

define Dockerfile.mytool
FROM alpine:3.21.2
RUN apk add --no-cache make bash
endef

$(call docker.import, def=Dockerfile.mytool namespace=mytool)
