#!/usr/bin/env -S bash -x -euo pipefail
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
#
# USAGE: bash -x tests/proxy-wrappers.sh

# Generate JSON with jb
./compose.mk jb key=val | jq -e .key
#{"key":"val"}

# Generate JSON with jb (alternate)
echo key=val | ./compose.mk jb | jq -e .key

# Parse JSON with jq
./compose.mk jb key=val | ./compose.mk jq .key
# "val"

# Passing arguments to jq works, so lets go raw and unquote it
./compose.mk jb key=val | ./compose.mk jq -e -r .key

# Now try yaml input, with yq
echo "key: val" | ./compose.mk yq -e .key