# demos/platform-lme.mk: 
#   Elaborating the `platform.mk` demo to including handlers for logging, metrics, and events.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/platform-lme.mk bootstrap
#
# Implementing a fake setup for platform bootstrap:
#   1. Infrastructure is configured by the terraform container, 
#   2. Application is configured by the ansible container,
#   3. Assume both tasks emit json events (simulating terraform state output, etc)

# Import the contents of the last demo so we can elaborate on it here.
include demos/platform.mk 
.DEFAULT_GOAL=demo.lme
# Fake some handlers for logging, metrics, events.

# 1. Logging uses the `elk` container,
logging: ▰/elk/self.logging
self.logging:
	$(call log.target, pretending to push log data somewhere)
	${stream.stdin} | ${jq} .log

# 2. Metrics uses the `prometheus` container,
metrics: ▰/prometheus/self.metrics
self.metrics:
	$(call log.target, pretending to do stuff with the promtool CLI)
	${stream.stdin} | ${jq} .metric

# 3. Events uses the `datadog` container.
events: ▰/datadog/self.events
self.events:
	$(call log.target, pretending to do stuff with the datadog CLI)
	${stream.stdin} | ${jq} .event

# Bind all handlers into a single pipe
downstream_handlers: flux.dmux/logging,metrics,events

# Send the `platform.setup` output into a handler-target for each LME backend
demo.lme: flux.pipeline/platform.setup,downstream_handlers

