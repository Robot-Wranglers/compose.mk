# Integration fixture: a service that stays up and has make, so <svc>.exec/<target> can run.
include compose.mk

$(call compose.import, file=dc.yml)

hello:
	@echo hello-cmk-exec

leave.mark:
	@echo exec-detach-ok > mark.txt
