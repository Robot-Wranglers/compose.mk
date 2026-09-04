# compose.mk test-suite

Assertion-bearing tests that drive the real `./compose.mk` entrypoint as a
subprocess. (The `demos/` files are run as docs/smoke tests elsewhere and stay
assertion-free; these are where behavior is actually asserted.)

Everything here is self-contained: `tox.ini`, `pytest.ini`, `ruff.toml`,
`requirements-test.txt`, and a `Makefile` of entrypoints. `tox` provisions
`pytest` + `ruff` into an isolated venv, so the system Python is untouched.

## Layout

| Path | Purpose |
|------|---------|
| `conftest.py` | the `cmk(*args, stdin=, env=, cwd=)` fixture + docker auto-skip |
| `test_unit_streams.py` | unit tests for the pure `stream.*` transforms |
| `test_unit_flux.py` | unit tests for the `flux.*` control-flow / algebra targets |
| `test_smoke_scripts.py` | wraps each `scripts/*.sh` and asserts a clean exit |
| `test_docker.py` | the `docker.*` target suite (label-scoped, self-cleaning) |
| `test_docker_io.py` / `test_docker_stream.py` | docker-gated `io.*` / `stream.*` targets |
| `test_integration_dockerfile.py` | scaffold a mini-project + build `Dockerfile.*` |
| `test_integration_reflection.py` | self-parse reflection (`mk.parse`, `*.help`) via a scaffold |
| `test_integration_compose.py` | `compose.*` (services/validate/images + `compose.import` dispatch) |
| `test_compiler_cmk.py` | CMK compiler — pure `mk.compile`/`lang.comp.pipeline.*` transforms |
| `scripts/*.sh` | legacy bash smoke scripts (now driven by the `smoke` env) |
| `fixtures/<name>/` | prebuilt project trees loaded by the `project` fixture |
| `tox.ini` | tox envs: `normalize`, `fix`, `unit`, `smoke`, `docker` (+ `integration`/`compiler` later) |
| `pytest.ini` | pytest config + markers (suites + `needs_docker`/`network` gates) |
| `ruff.toml` | style config (2-space indent, 79-col lines) |

## Usage

From this directory:

```bash
make            # default: install tox + run the unit suite
make unit-test  # fast, no-docker unit tests (alias: make units)
make smoke-test # wrap scripts/*.sh, assert clean exit (alias: make smoke; needs docker)
make docker-test # the docker.* target suite (needs a daemon)
make integration-test # scaffold a mini-project + run targets (needs a daemon)
make compiler-test # pure CMK->Makefile transpile tests (no docker)
make coverage   # target-level coverage report (direct; report-only)
make normalize  # auto-apply ruff formatting + lint fixes, then verify
make tox        # normalize + units together
make init       # install tox (once); tox then provisions pytest/ruff
```

From the repo root (delegating entrypoints):

```bash
make unit-test    # installs tox + runs the unit suite (delegates to tests/)
make smoke-test   # installs tox + runs the smoke suite (delegates to tests/)
make docker-test  # installs tox + runs the docker.* suite (delegates to tests/)
make integration-test  # installs tox + runs the integration suite (tests/)
make coverage     # installs tox + runs the coverage report (delegates to tests/)
make test         # full project suite; runs unit + docker + smoke + ...
```

Docker tests are gated and skipped when no daemon is reachable (or free disk on
the docker data-root is below `CMK_TEST_MIN_DISK_GB`, default 3). Network builds
are skipped unless `CMK_TEST_NETWORK=1`. `CMK_TEST_KEEP_IMAGES=1` keeps built
images for fast local re-runs.

You can also target tox or pytest directly:

```bash
tox -e unit                 # one env
tox -e unit -- -k comma -v  # extra pytest args after `--`
tox -e unit -- -n auto      # parallel (pytest-xdist)
```

## Integration tests (`project` fixture)

Integration tests (`@pytest.mark.integration, needs_docker`) scaffold a real
mini-project in a temp dir and run targets against it, via the `project`
fixture:

```python
def test_x(project, runid):
  project.write("Dockerfile", "FROM alpine:3.21.2\n")   # inline
  r = project.run("Dockerfile.from.fs/Dockerfile", env={"tag": "compose.mk:x"})
  assert r.ok

def test_y(project):
  project.load("dockerfile-def")     # copy tests/fixtures/dockerfile-def/ in
  assert project.run("Dockerfile.build/app").ok
```

- `project.write(path, text)` / `project.makefile(body)` — inline scaffolding
  (`makefile` prepends `include <abs>/compose.mk`).
- `project.load(name)` — copy `tests/fixtures/<name>/` into the project dir; when
  the tree has a `Makefile`, a copy of compose.mk is placed alongside so a
  natural `include compose.mk` resolves (that copy is git-ignored).
- `project.run(target, ...)` — drive it through `docker_cmk` (cwd = project dir;
  auto-uses a scaffolded `Makefile` via `make -f`). Everything is `cmktest`-
  labeled and swept on teardown, same as the docker suite.

Add reusable multi-file trees under `tests/fixtures/<name>/`; they're committed
source (not generated). The scaffold also unlocks **self-parse reflection**
(`mk.parse`, `mk.namespace.filter`, `*.help`) — these route through the `mkparse`
container, which parses the makefile from the mounted cwd, so they only work
from a real project dir (`project.run` pins `DOCKER_HOST_WORKSPACE` to it). This
layer will grow to cover `compose.import` / `docker.import` / `loadf`.

## Target coverage

`make coverage` runs unit + smoke + docker in one session and reports **direct
target-level coverage** — which of compose.mk's public targets the suite
actually invokes. It's **report-only** (never fails) and gated on
`CMK_TEST_COVERAGE=1` (set by the `coverage` tox env), so normal runs stay quiet.

- *Numerator*: targets invoked via the `cmk`/`docker_cmk` fixtures, plus targets
  statically parsed from the `scripts/*.sh` that ran (smoke).
- *Denominator*: an independent static parse of `compose.mk` (`tests/_targets.py`).
  The tool's own `mk.parse` is shown only as a cross-check — it's under test, so
  it doesn't define the metric. A large divergence is itself a parser-bug smell.
- *Direct only*: transitively-invoked targets (e.g. `docker.run.sh` reached via
  `docker.dispatch`) are **not** credited — this is a deliberate, honest floor.
- Artifacts: `tests/.coverage-targets.json` + `tests/coverage-targets.md`
  (git-ignored) list covered/uncovered targets per namespace.

## Style

Run `make normalize` to auto-format and verify; CI fails if committed code
isn't already normalized.

## Conventions

- **Test against intended behavior, not a snapshot.** Expected values are
  derived from real output but reviewed against each target's docstring.
- **Known bugs are pinned, not hidden.** Where the code review found a real
  defect, the test asserts the *correct* result and is marked
  `@pytest.mark.xfail(..., strict=False)` with a `compose.mk:LINE; review SEV`
  pointer. It stays as XFAIL until fixed, then flips to XPASS.
- **Isolation.** The `cmk` fixture defaults `cwd` to a pytest `tmp_path`, so
  scratch files (`io.mktemp`'s `./.tmp.*`, `.stage.*`) never touch the repo.
- **Docker gating.** `needs_docker` is the capability gate (auto-skip without a
  daemon / on low disk); the suite *selectors* are `unit`/`smoke`/`docker`/...
  So `tox -e docker` runs only the docker.* suite, not every docker-needing test.
- **Docker cleanup is label-scoped, never global.** Every container/image the
  docker suite creates is tagged `cmktest=<RUNID>` (injected via compose.mk's
  `docker_args`); teardown removes only those — pulled base images and the
  developer's unrelated state are left untouched. The destructive compose.mk
  targets (`docker.stop.all`, `docker.panic`, `docker.system.prune`) are never
  called. Cleanup also fires on Ctrl-C / timeout (`pytest_keyboard_interrupt`,
  `pytest_sessionfinish`, session finalizer), killing in-flight subprocesses.
