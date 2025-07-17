#!/usr/bin/env -S make -f
# Demonstrating import shell-script to target.
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
# USAGE: ./demos/script-dispatch-stock.mk

include compose.mk

# Look, here's a simple shell script 
define script.sh
set -x
printf "multiline stuff\n"
for i in $(seq 2); do
    echo "Iteration $i"
done
endef

# Directly imports script to target of same name.
$(call compose.import.script, def=script.sh)

__main__: 
	$(call log.test, Running embedded script)
	${make} script.sh | grep 'Iteration 2'