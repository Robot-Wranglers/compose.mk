#!/usr/bin/env bash

# Stages real bytes for npm to pack, since npm's packer drops symlinks.  See ./README.md.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
staged="${here}/_bundled"
plugins="${staged}/plugins"

src_tool="${here}/compose.mk"
src_wrapper="${here}/../pip/cmk"
src_plugins="${here}/../../.cmk"

mkdir -p -- "${staged}"

if [ -e "${src_tool}" ]; then
  cp -L -- "${src_tool}" "${staged}/compose.mk"
  chmod 0755 "${staged}/compose.mk"
elif [ ! -s "${staged}/compose.mk" ]; then
  echo "compose-mk: cannot find compose.mk to bundle (looked at ${src_tool})" >&2
  exit 1
fi

# The cmk frontend is shared verbatim with the pip shim; there is one wrapper.
if [ -e "${src_wrapper}" ]; then
  cp -L -- "${src_wrapper}" "${staged}/cmk"
  chmod 0755 "${staged}/cmk"
elif [ ! -s "${staged}/cmk" ]; then
  echo "compose-mk: cannot find the cmk wrapper to bundle (looked at ${src_wrapper})" >&2
  exit 1
fi

# Shippable stdlib plugins, minus the submodule's vendored core and scratch cruft.
staged_any=0
if [ -d "${src_plugins}" ]; then
  mkdir -p -- "${plugins}"
  for f in "${src_plugins}"/*.mk "${src_plugins}"/*.cmk; do
    [ -f "${f}" ] || continue
    base="$(basename -- "${f}")"
    case "${base}" in compose.mk | .tmp.*) continue ;; esac
    cp -p -- "${f}" "${plugins}/${base}"
    staged_any=1
  done
fi

if [ "${staged_any}" -eq 0 ] && ! ls "${plugins}"/*.mk "${plugins}"/*.cmk >/dev/null 2>&1; then
  echo "compose-mk: warning -- no CMK plugins bundled (the .cmk submodule was not found at" \
    "${src_plugins}; did you init submodules?).  The cmk repl and the polyglot plugins" \
    "will need a project-local .cmk dir." >&2
fi
