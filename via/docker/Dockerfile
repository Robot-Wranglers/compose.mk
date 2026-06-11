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
# The CMK compiler's awk stages need GNU awk (not busybox/mawk). docker-cli plus
# the compose plugin let a containerized compose.mk drive the shared host socket
# and `docker compose` (the Make/Compose bridge). coreutils for GNU utils.
RUN apk add --no-cache bash make jq gawk coreutils git docker-cli docker-cli-compose
ADD https://raw.githubusercontent.com/${CMK_REPO}/${CMK_REF}/compose.mk /usr/local/bin/compose.mk
RUN chmod 0755 /usr/local/bin/compose.mk
WORKDIR /workspace

# Belt-and-suspenders perf defaults. compose.mk now defines its OS_NAME/DOCKER_UID/
# DOCKER_GID probes as simply-expanded (`:=`), evaluated once -- so this bake only
# matters when building from a CMK_REF that predates that fix, where GNU make 4.4
# (alpine's) would otherwise re-run each probe's `$(shell)` for every parse-time
# $(shell) (hundreds; ~40x slower). Harmless and correct for a root/Linux image;
# DOCKER_UID/GID stay overridable at runtime (e.g. host-matching file ownership).
ENV OS_NAME=Linux \
    DOCKER_UID=0 \
    DOCKER_GID=0

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
