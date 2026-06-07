# Integration fixture: imports a compose file whose service builds a tiny image
# and stays up (sleep), so the generated build + running-container target
# families can be exercised. The `project` fixture copies compose.mk in.
include compose.mk

$(call compose.import, file=dc.yml)
