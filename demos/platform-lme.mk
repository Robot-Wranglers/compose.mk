#!/usr/bin/env -S make -f
# demos/platform-lme.mk: 
#  Elaborating the `platform.mk` demo to include handlers for logging, metrics, & events.
#  We use namespace-style dispatch here to run commands in docker, and use `compose.mk`
#  workflows to describe data-flow. 
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# See the main docs:  http://robot-wranglers.github.io/compose.mk/demos/platform/
# USAGE: ./demos/platform-lme.mk

# Import the contents of the last demo so we can elaborate on it here.
include demos/platform.mk 
.DEFAULT_GOAL=platform.setup.observable

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
downstream_handlers: flux.pipe.fork/logging,metrics,events

# Send the `platform.setup.basic` output into a handler-target for each LME backend
platform.setup.observable: flux.pipeline/platform.setup.basic,downstream_handlers

