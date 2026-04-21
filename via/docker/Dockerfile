# via/docker -- a "compose.mk in a box" image (see ./README.md).
#
# Unlike via/pip and via/npm (which ship `compose.mk` as a symlink to the repo
# root and let the package backend dereference it on a full checkout), this shim
# is built straight from a git ref + subdir:
#
#   docker build -t compose.mk \
#     https://github.com/Robot-Wranglers/compose.mk.git#main:via/docker
#
# In that mode the build context is ONLY this directory, so a `../../compose.mk`
# symlink would be out-of-context and dangling. We therefore FETCH compose.mk at
# the same ref via `ADD`, parameterized by build-args (default: the default
# branch). Pin a release with, e.g. `--build-arg CMK_REF=v1.2.42 ...#v1.2.42:via/docker`.

# --- base: runtime deps + compose.mk on PATH -------------------------------
FROM alpine:3.21.2 AS base
ARG CMK_REPO=Robot-Wranglers/compose.mk
ARG CMK_REF=main
# The stdlib CMK plugins live in their OWN repo (the `.cmk` submodule).  We bundle
# them (below) so plugin-dependent features work out of the box; track the rolling
# stdlib by default, or pin with `--build-arg CMK_PLUGINS_REF=<sha-or-tag>`.
ARG CMK_PLUGINS_REPO=Robot-Wranglers/.cmk
ARG CMK_PLUGINS_REF=main
# The CMK compiler's awk stages need GNU awk (not busybox/mawk). docker-cli plus
# the compose plugin let a containerized compose.mk drive the shared host socket
# and `docker compose` (the Make/Compose bridge). coreutils for GNU utils.
RUN apk add --no-cache bash make jq gawk coreutils git docker-cli docker-cli-compose
ADD https://raw.githubusercontent.com/${CMK_REPO}/${CMK_REF}/compose.mk /usr/local/bin/compose.mk
RUN chmod 0755 /usr/local/bin/compose.mk

# Bundle the shippable stdlib plugins into <prefix>/share/compose.mk/cmk (mirrors
# via/pip's layout), so `cmk repl`, polyglots, the VM, gitops, etc. work without a
# project-local ./.cmk.  Shippable = top-level *.mk/*.cmk EXCEPT the submodule's own
# vendored `compose.mk` and any tmp/scratch.  Cloned at build time so this also works
# for the public `docker build <repo>#<ref>:via/docker` (git-url builds don't init
# submodules).  git is already installed above and stays for the gitops plugin.
RUN set -eu; \
    git clone -q https://github.com/${CMK_PLUGINS_REPO}.git /tmp/cmk-src; \
    git -C /tmp/cmk-src checkout -q "${CMK_PLUGINS_REF}"; \
    mkdir -p /usr/local/share/compose.mk/cmk; \
    for f in /tmp/cmk-src/*.mk /tmp/cmk-src/*.cmk; do \
      [ -e "$f" ] || continue; \
      b=$(basename "$f"); \
      case "$b" in compose.mk|.tmp.*) continue;; esac; \
      cp "$f" /usr/local/share/compose.mk/cmk/; \
    done; \
    rm -rf /tmp/cmk-src; \
    echo "bundled plugins:"; ls -1 /usr/local/share/compose.mk/cmk

WORKDIR /workspace

# Belt-and-suspenders perf defaults. compose.mk now defines its OS_NAME/DOCKER_UID/
# DOCKER_GID probes as simply-expanded (`:=`), evaluated once -- so this bake only
# matters when building from a CMK_REF that predates that fix, where GNU make 4.4
# (alpine's) would otherwise re-run each probe's `$(shell)` for every parse-time
# $(shell) (hundreds; ~40x slower). Harmless and correct for a root/Linux image;
# DOCKER_UID/GID stay overridable at runtime (e.g. host-matching file ownership).
#
# CMK_PLUGINS_DIR is a `:`-separated search PATH: a project-local `./.cmk` is tried
# FIRST (so a mounted project can override/extend), then the bundled stdlib.
# CMK_MODULES_DIR (the writable JIT staging dir) stays the working-dir-relative first
# element -- override it (e.g. CMK_MODULES_DIR=/tmp/cmk) for a read-only workdir.
ENV OS_NAME=Linux \
    DOCKER_UID=0 \
    DOCKER_GID=0 \
    CMK_PLUGINS_DIR=.cmk:/usr/local/share/compose.mk/cmk \
    CMK_MODULES_DIR=.cmk

# --- test: base + python harness, so the image can run compose.mk's OWN suite
#     (mount the repo at /workspace, share the docker socket). Built on demand:
#       docker build --target test -t compose.mk:test via/docker
FROM base AS test
RUN apk add --no-cache python3 py3-pip py3-virtualenv
RUN pip install --no-cache-dir --break-system-packages tox
ENTRYPOINT ["sh"]

# --- runtime: the published / `FROM`-able image. LAST stage, so a plain
#     `docker build` (no --target) produces this lean image, not the test one.
FROM base AS runtime
ENTRYPOINT ["compose.mk"]
