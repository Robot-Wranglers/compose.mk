#!/usr/bin/env -S make -f
#
# kwarg-parsing-2.mk:
#   Building on demos/structured-io.mk to demonstrate parsing structured
#   arguments.
#
# USAGE: ./demos/kwarg-parsing-2.mk

include compose.mk

# Or pass it from the command line..
export shape?=circle

__main__:
	$(call bind.args, from=env, shape=default color=blue) \
	&& printf "shape=$${shape} color=$${color}\n"
