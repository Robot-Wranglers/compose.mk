# Integration fixture: compose.import.code generates targets that operate on a
# named define-block (read / write-to-file / preview / run). No container.
include compose.mk

define greeting
echo CODE-BLOCK-OK
endef

$(call compose.import.code, def=greeting namespace=greet)
