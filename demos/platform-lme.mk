# demos/platform-lme.mk: 
#   Elaborating the `platform.mk` demo to including logging, metrics, and event handlers.
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

# Fake some handlers for logging, metrics, events.
#   1. Logging uses the `elk` container,
#   2. Metrics uses the `prometheus` container,
#   3. Events uses the `datadog` container.
logging: ▰/elk/self.logging
self.logging:
	# pretending to push data somewhere with curl
	cat /dev/stdin | jq .log

metrics: ▰/prometheus/self.metrics
self.metrics:
	# pretending to do stuff with the promtool CLI
	cat /dev/stdin | jq .metric

events: ▰/datadog/self.events
self.events:
	# pretending to do stuff with the datadog CLI
	cat /dev/stdin | jq .event

bootstrap:
	# pipes all the platform.setup output into a handler-target for each LME backend
	make platform.setup | make flux.dmux/logging,metrics,events

