#!/usr/bin/env -S make -f
# Demonstrating idioms for container-agnostic script dispatch with 
# compose-file backed tool containers. The target script always runs 
# from the container, but does not care whether it's called from the host,
# or from inside the container.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/container-dispatch
#
# USAGE: ./demos/bind-script.mk


include compose.mk
$(call compose.import, file=demos/data/docker-compose.yml)

export var1=shared
export var2=data

# Decorator-style idiom.
# This binds together a script, a target, and a container,
# using the given target name as the public interface.  
# Typically the define-name and target-name will be the same.
# It also shares a subset of the available environment variables
script.sh:; $(call compose.bind.script, svc=alpine env='var1 var2' quiet=1)
define script.sh
echo hello container `hostname`
echo testing environment variables: ${var1} ${var2}
endef

# Test that target still works, no matter where it's called from.
__main__:
	${make} script.sh
	${make} debian.dispatch/script.sh | grep 'hello container'

