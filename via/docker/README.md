# via/docker — run compose.mk from a container

A docker packaging shim: a small image with `compose.mk` on `PATH` plus its
runtime deps (`bash make jq gawk coreutils`) and the docker CLI + compose plugin,
so a *containerized* `compose.mk` can still orchestrate **sibling** tool-containers
on the host daemon.

This is **additive**: the normal drop-in usage (download `compose.mk` into your
project, `include compose.mk` / `./compose.mk`) is unchanged and remains the
default; running from a container is just another option. See also `via/pip`,
`via/npm`, and `via/basher` for putting `compose.mk` on the *host* PATH.

## Get the image

Build straight from a git ref + subdirectory (no checkout needed):

```bash
# default branch:
docker build -t compose.mk \
  https://github.com/Robot-Wranglers/compose.mk.git#main:via/docker

# pin a tag/branch/commit (keep the build-arg in sync with the ref):
docker build -t compose.mk:v1.2.42 --build-arg CMK_REF=v1.2.42 \
  https://github.com/Robot-Wranglers/compose.mk.git#v1.2.42:via/docker
```

The Dockerfile fetches `compose.mk` at `CMK_REF` (default `main`) — the
build context is only this subdir, so it can't rely on the repo-root file.

Or pull a prebuilt multi-arch image (published to GHCR on releases):

```bash
docker pull ghcr.io/robot-wranglers/compose.mk:latest
```

## Run compose.mk from the container

The image's entrypoint **is** `compose.mk`, so arguments are targets:

```bash
docker run --rm -it \
  -v /var/run/docker.sock:/var/run/docker.sock \   # drive the host docker daemon
  -v "$PWD:$PWD" -w "$PWD" \                        # mount the project at its OWN path
  -e DOCKER_HOST_WORKSPACE="$PWD" \                 # see note below
  compose.mk flux.ok
```

What each flag is for:

- **`-v /var/run/docker.sock:/var/run/docker.sock`** — compose.mk's model is to run
  tools *in containers*. Sharing the host socket lets the containerized compose.mk
  start those as **siblings** on the host daemon (this is socket-sharing, not
  isolated docker-in-docker). Override the socket path with `-e DOCKER_SOCKET=...`.
- **`-v "$PWD:$PWD" -w "$PWD"` — mount at the *same* path, not `/workspace`.** Sibling
  containers are created by the *host* daemon, so any path compose.mk hands to docker
  must be valid **on the host**. Mounting your project at its own host path (and
  `cd`-ing there) makes in-container paths equal host paths, so the files/sockets/
  source compose.mk bind-mounts into siblings line up. (Remapping to `/workspace`
  works for trivial host-only targets but breaks container-dispatch, where a sibling
  would be told to mount a `/workspace` path the host can't see.)
- **`-e DOCKER_HOST_WORKSPACE="$PWD"`** — the workspace root compose.mk shares into
  the tool-containers it spawns; set it to the same host path you mounted.

A shell instead of a target:

```bash
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:$PWD" -w "$PWD" -e DOCKER_HOST_WORKSPACE="$PWD" \
  --entrypoint sh compose.mk
```

### Container dispatch (running *your* project)

When a target spawns tool-containers (the Make/Compose bridge / `compose.import`,
`*.dispatch/<target>`, `docker.dispatch/<target>`), those siblings need `compose.mk`
itself. The robust way is the normal compose.mk model: **vendor `compose.mk` into
your project** (so it rides along in the shared workspace mount) and run *that* copy,
with the same-path mount above:

```bash
# project has ./compose.mk + a Makefile that `include`s it
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:$PWD" -w "$PWD" -e DOCKER_HOST_WORKSPACE="$PWD" \
  --entrypoint make compose.mk <your-target>
```

(The image's bundled `compose.mk` lives at `/usr/local/bin` — great for the
self-contained tool targets above and for `FROM`, but for dispatch use the in-project
copy so the host daemon can mount it into siblings.)

## Use as a base image

The image is also `FROM`-able, so your own app can build on it. For example, an
app whose `backend/` dir contains:

```dockerfile
# backend/Dockerfile
FROM ghcr.io/robot-wranglers/compose.mk:latest
COPY . /workspace
# ... your services/targets; override ENTRYPOINT/CMD as needed ...
```

built directly from its git ref + subdir:

```bash
docker build -t my-backend \
  https://github.com/your-org/your-app.git#main:backend
```

and run with the same socket/workspace flags shown above.

## Run the test suite from the container (dev / CI)

The Dockerfile has a `test` stage that adds a python harness (`tox`), so the image
can run compose.mk's **own** suite — a useful dogfood/CI check that the
containerized tool is fully wired (including socket-backed, sibling-container
tests):

```bash
docker build --target test -t compose.mk:test \
  https://github.com/Robot-Wranglers/compose.mk.git#main:via/docker

REPO=$(pwd)   # a checkout of this repo, mounted at its own path (see above)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$REPO:$REPO" -w "$REPO/tests" \
  -e DOCKER_HOST_WORKSPACE="$REPO" \
  -e TOX_WORK_DIR=/root/.tox \                       # venvs off the mount
  compose.mk:test -c 'tox -e unit && tox -e compiler'
```

The full suite (`make test`) runs the same way. One note: the docker-marked envs
additionally need the socket mount above plus a same-path `/tmp` share (`-v /tmp:/tmp`)
so the sibling containers can reach pytest's `tmp_path`.

> The image bakes `OS_NAME`/`DOCKER_UID`/`DOCKER_GID` (see the Dockerfile) as a
> belt-and-suspenders perf default. compose.mk now defines those probes as
> simply-expanded (`:=`), so they're evaluated once; the bake only matters when
> building from an older `CMK_REF` predating that fix, where **GNU make 4.4** (alpine's)
> would otherwise re-run each probe's `$(shell)` for every parse-time `$(shell)`
> (~40x slower than make 4.3).

## Caveats

- **File ownership.** The container runs as root, so files it writes to
  `/workspace` are root-owned on the host. Set `-e DOCKER_UID=$(id -u)
  -e DOCKER_GID=$(id -g) -e DOCKER_UGNAME=$(id -un)` to have spawned tool
  containers use your identity.
- **Shared daemon, not isolation.** Sibling containers run on the host daemon and
  can see/affect it. This is intended (it's how compose.mk works), not sandboxing.
- **Lean base.** The image carries the essentials; very heavy features (the
  embedded TUI, `yq`-driven targets, etc.) may need extra packages — extend the
  image (`FROM` it and `apk add ...`) for those.

## Requirements

Only docker on the host. Everything compose.mk needs at runtime (GNU `make`/`awk`,
`bash`, `jq`, docker CLI + compose plugin) is in the image.
