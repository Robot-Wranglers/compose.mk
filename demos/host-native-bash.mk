#!/usr/bin/env -S make -f
#
# host-native-bash.mk: dispatch a shell script on the host.
#
# USAGE: ./demos/host-native-bash.mk

include compose.mk

# Look, here's a simple shell script.
define script.sh
set -x
printf "multiline stuff\n"
for i in $(seq 2); do
    echo "Iteration $i"
done
endef

# Bind the script define-block to the core host.native.bash machine.
$(call code.import, pattern=script[.]sh bind=host.native.bash)

__main__: script.sh