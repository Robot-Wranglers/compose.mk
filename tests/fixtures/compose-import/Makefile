# Integration fixture: a project that imports a compose file and exposes the
# generated <service>.dispatch/<target> targets. The `project` fixture copies
# compose.mk in, so `include compose.mk` resolves.
include compose.mk

$(call compose.import, file=dc.yml)

hello:; @echo HELLO-CMK-COMPOSE
