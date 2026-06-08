"""Shared pytest harness for the compose.mk test-suite.

The suite drives the real ``./compose.mk`` entrypoint as a subprocess and
asserts on its output. Layers: unit (``stream.*``/``flux.*``), smoke (the
``tests/scripts/*.sh`` wrappers), and docker (the ``docker.*`` targets).

Docker safety: every container/image the docker suite creates is tagged with a
unique per-session label (``cmktest=<RUNID>``, injected via compose.mk's
``docker_args`` passthrough). Cleanup only ever removes resources carrying that
label, so it can never touch the developer's unrelated docker state or the
pulled base-image download cache. Global teardown targets (docker.stop.all,
docker.panic, docker.system.prune, ...) are never used.
"""

import json
import os
import shutil
import signal
import subprocess
import uuid
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import pytest

from _targets import (
  alias_map,
  base_name,
  coverage_markdown,
  coverage_report,
  generated_report,
  mk_parse_targets,
  public_targets,
  targets_in_script,
)

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"
SCRIPTS_DIR = REPO / "tests" / "scripts"

# --- target-coverage recording (report-only; gated by CMK_TEST_COVERAGE) ----
# Base names of targets invoked via the fixtures, and which suite markers
# actually executed (so smoke scripts are credited only when smoke ran).
_INVOKED_TARGETS: set = set()
_RAN_SUITES: set = set()

# One label per test session; scopes all docker cleanup.
RUNID = uuid.uuid4().hex[:12]
CMKTEST_LABEL = f"cmktest={RUNID}"
# Scoped `docker compose` project name (valid: lowercase alnum). compose labels
# its containers/networks com.docker.compose.project=<this>, so cleanup can
# sweep the network it creates (which doesn't carry our docker_args label).
COMPOSE_PROJECT = f"cmktest{RUNID}"

# Minimum free disk (GB) on the docker data root before the docker suite runs.
MIN_DISK_GB = float(os.environ.get("CMK_TEST_MIN_DISK_GB", "3"))

# Deterministic, non-interactive, color-free environment so that stdout carries
# only the functional result (all log.* output goes to stderr) and there are no
# ANSI escapes, supervisor wrappers, or target-rewrite hooks to assert around.
#
#   NO_COLOR=1          -> zeroes every ansi color var (compose.mk:68)
#   CMK_SUPERVISOR=0    -> skip the signal/supervisor wrapper (compose.mk:29)
#   CMK_INTERNAL=1      -> no DIND / import side effects; right default for the
#                          no-docker layers. The docker_cmk fixture flips this
#                          back to "0" so *.dispatch/ actually runs containers.
#   CMK_DISABLE_HOOKS=1 -> skip target-rewrite + at-exit hooks (compose.mk:38)
#   TERM=dumb, TRACE=0  -> no terminal/tracing noise
BASE_ENV = {
  "NO_COLOR": "1",
  "CMK_SUPERVISOR": "0",
  "CMK_INTERNAL": "1",
  "CMK_DISABLE_HOOKS": "1",
  "TERM": "dumb",
  "TRACE": "0",
  "GITHUB_ACTIONS": "false",
}


@dataclass
class Result:
  """Outcome of one ``./compose.mk`` invocation."""

  stdout: str
  stderr: str
  returncode: int

  @property
  def ok(self) -> bool:
    return self.returncode == 0


@pytest.fixture
def cmk(tmp_path):
  """Run ``./compose.mk <args>`` with the deterministic env, capturing output.

  Usage::

      r = cmk("stream.comma.to.nl", stdin="a,b,c")
      assert r.ok and r.stdout == "a\\nb\\nc"

  cwd defaults to a pytest ``tmp_path`` so scratch files (``io.mktemp``'s
  ``./.tmp.*`` and ``.flux.stage.*``) land in the temp dir and never pollute
  the repo; pytest removes the dir afterwards.
  """

  def run(*args, stdin="", env=None, cwd=None, makefile=None) -> Result:
    if args:
      _INVOKED_TARGETS.add(base_name(args[0]))
    merged = {**os.environ, **BASE_ENV, **(env or {})}
    # A wrapper makefile (which `include`s compose.mk) lets a test supply its
    # own defs/targets, e.g. a `define` for mk.def.read.
    argv = (
      ["make", "-f", str(makefile), *args]
      if makefile
      else [str(COMPOSE_MK), *args]
    )
    proc = subprocess.run(
      argv,
      input=stdin,
      text=True,
      capture_output=True,
      cwd=str(cwd or tmp_path),
      env=merged,
    )
    return Result(proc.stdout, proc.stderr, proc.returncode)

  return run


# --- Docker machinery -------------------------------------------------------

# Live ./compose.mk subprocesses, so an interrupt can kill them (and their
# child `docker` clients / containers) instead of leaking.
_LIVE_PROCS: set = set()


def _docker_available() -> bool:
  if not shutil.which("docker"):
    return False
  try:
    cp = subprocess.run(["docker", "info"], capture_output=True)
    return cp.returncode == 0
  except Exception:
    return False


def _docker_root() -> str:
  try:
    cp = subprocess.run(
      ["docker", "info", "-f", "{{.DockerRootDir}}"],
      capture_output=True,
      text=True,
    )
    return cp.stdout.strip() or "/"
  except Exception:
    return "/"


def _enough_disk() -> bool:
  try:
    free_gb = shutil.disk_usage(_docker_root()).free / 2**30
  except OSError:
    return True
  return free_gb >= MIN_DISK_GB


def _kill_proc_group(proc) -> None:
  try:
    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
  except (ProcessLookupError, PermissionError, OSError):
    pass


def _docker_ids(kind: str, label: str) -> list:
  """ids of containers / images / networks carrying the given label."""
  base = {
    "containers": ["docker", "ps", "-aq"],
    "images": ["docker", "images", "-q"],
    "networks": ["docker", "network", "ls", "-q"],
  }[kind]
  args = [*base, "--filter", f"label={label}"]
  try:
    out = subprocess.run(args, capture_output=True, text=True).stdout
    return list(dict.fromkeys(out.split()))
  except Exception:
    return []


def _rm(cmd: list, ids: list) -> None:
  if ids:
    try:
      subprocess.run([*cmd, *ids], capture_output=True)
    except Exception:
      pass


def scoped_cleanup() -> None:
  """Remove only THIS session's resources. Idempotent.

  Sweeps by two labels: our ``cmktest=<RUNID>`` (containers/images created via
  docker_cmk's docker_args) and the compose project
  ``com.docker.compose.project=<COMPOSE_PROJECT>`` (containers/networks/images
  `docker compose` creates, which don't carry our docker_args label). Never
  touches base images or anything we didn't scope, so it's safe on a dev box.
  CMK_TEST_KEEP_IMAGES=1 keeps built images.
  """
  if not _docker_available():
    return
  proj = f"com.docker.compose.project={COMPOSE_PROJECT}"
  _rm(["docker", "rm", "-f"], _docker_ids("containers", CMKTEST_LABEL))
  _rm(["docker", "rm", "-f"], _docker_ids("containers", proj))
  _rm(["docker", "network", "rm"], _docker_ids("networks", proj))
  if os.environ.get("CMK_TEST_KEEP_IMAGES") == "1":
    return
  _rm(["docker", "rmi", "-f"], _docker_ids("images", CMKTEST_LABEL))
  _rm(["docker", "rmi", "-f"], _docker_ids("images", proj))


def _sweep_stale() -> None:
  """Reclaim resources leaked by previously-interrupted harness runs.

  The ``cmktest`` label and ``cmktest*`` compose-project network names are
  exclusively ours, so this is safe — but it assumes no *concurrent* harness
  session (we run docker suites serially). Respects CMK_TEST_KEEP_IMAGES.
  """
  if not _docker_available():
    return
  _rm(["docker", "rm", "-f"], _docker_ids("containers", "cmktest"))
  try:
    names = subprocess.run(
      ["docker", "network", "ls", "--format", "{{.Name}}"],
      capture_output=True,
      text=True,
    ).stdout.split()
    _rm(["docker", "network", "rm"], [n for n in names if "cmktest" in n])
  except Exception:
    pass
  if os.environ.get("CMK_TEST_KEEP_IMAGES") != "1":
    _rm(["docker", "rmi", "-f"], _docker_ids("images", "cmktest"))


@pytest.fixture(scope="session", autouse=True)
def _docker_session():
  """Sweep stale (interrupted-run) resources up front, ours on teardown."""
  _sweep_stale()
  yield
  scoped_cleanup()


@pytest.fixture
def docker_cmk(tmp_path):
  """Like ``cmk`` but for the docker suite.

  Forces ``CMK_INTERNAL=0`` (so ``*.dispatch/`` really runs containers) and
  injects ``docker_args=--label cmktest=<RUNID>`` (merged with any caller
  ``docker_args``) so every container/image is cleanable by label. Runs in its
  own process group; on timeout the group is killed and the labeled resources
  swept.
  """

  def run(*args, stdin="", env=None, cwd=None, timeout=300, makefile=None):
    if args:
      _INVOKED_TARGETS.add(base_name(args[0]))
    run_cwd = Path(cwd) if cwd else tmp_path
    extra = dict(env or {})
    existing = extra.get("docker_args", "").strip()
    label = f"--label {CMKTEST_LABEL}"
    extra["docker_args"] = f"{existing} {label}".strip() if existing else label
    extra.setdefault("CMK_INTERNAL", "0")
    # Pin the docker workspace mount to this run's cwd (the scaffold),
    # overriding any DOCKER_HOST_WORKSPACE inherited from the outer make/tox,
    # so mount-based targets (mkparse reflection, docker.run.base) see it.
    extra.setdefault("DOCKER_HOST_WORKSPACE", str(run_cwd))
    # Scope `docker compose` resources so the network it creates is cleanable.
    extra.setdefault("COMPOSE_PROJECT_NAME", COMPOSE_PROJECT)
    merged = {**os.environ, **BASE_ENV, **extra}
    # A wrapper makefile (which `include`s compose.mk) lets a test supply its
    # own defs, e.g. a Dockerfile.<name> for docker.lambda. Otherwise run the
    # compose.mk entrypoint. Invoke it by a cwd-relative path when it lives
    # under cwd, so dispatch targets (which mount $PWD into the container and
    # re-run `make -f <path>`) see a path valid inside the /workspace mount.
    if makefile:
      argv = ["make", "-f", str(makefile), *args]
    else:
      rel = os.path.relpath(COMPOSE_MK, run_cwd)
      prog = str(COMPOSE_MK) if rel.startswith("..") else f"./{rel}"
      argv = [prog, *args]
    proc = subprocess.Popen(
      argv,
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      cwd=str(run_cwd),
      env=merged,
      start_new_session=True,
    )
    _LIVE_PROCS.add(proc)
    try:
      out, err = proc.communicate(input=stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
      _kill_proc_group(proc)
      out, err = proc.communicate()
      scoped_cleanup()
      raise
    finally:
      _LIVE_PROCS.discard(proc)
    return Result(out, err, proc.returncode)

  return run


@pytest.fixture
def runid() -> str:
  """The per-session id used in the cmktest label (for unique tags, etc.)."""
  return RUNID


# --- Integration scaffolding ------------------------------------------------


class Project:
  """A scaffolded mini-project in a temp dir for integration tests.

  Build it inline (``makefile``/``write``) or load a prebuilt tree from
  ``tests/fixtures/<name>/`` (``load``). ``run`` drives it through docker_cmk,
  so every container/image is cmktest-labeled and swept on teardown. When a
  ``Makefile`` is present, ``run`` invokes it via ``make -f`` automatically.
  """

  def __init__(self, directory, runner):
    self.dir = directory
    self._run = runner

  def write(self, relpath, text):
    path = self.dir / relpath
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path

  def _ensure_compose_mk(self):
    # Copy compose.mk into the project dir so a Makefile can use a natural
    # `include compose.mk` (resolves in cwd, and inside dispatch mounts too).
    dest = self.dir / "compose.mk"
    if not dest.exists():
      shutil.copy(COMPOSE_MK, dest)

  def seed_compose_mk(self):
    """Drop compose.mk into the project dir (no Makefile).

    For compiled-CMK runs: the compiled output is run as a Makefile that
    `include`s compose.mk, so it must be resolvable from the run cwd.
    """
    self._ensure_compose_mk()
    return self.dir / "compose.mk"

  def makefile(self, body):
    self._ensure_compose_mk()
    return self.write("Makefile", f"include compose.mk\n{body}\n")

  def load(self, name):
    """Copy tests/fixtures/<name>/ into the project dir.

    Fixture Makefiles use a normal ``include compose.mk``; a copy of compose.mk
    is placed alongside (when the tree has a Makefile) so the include resolves.
    """
    src = REPO / "tests" / "fixtures" / name
    shutil.copytree(src, self.dir, dirs_exist_ok=True)
    if (self.dir / "Makefile").exists():
      self._ensure_compose_mk()
    return self.dir

  def run(self, *args, **kw):
    kw.setdefault("cwd", self.dir)
    if (self.dir / "Makefile").exists():
      # Relative name (cwd is the project dir) so ${MAKEFILE} resolves inside
      # the mkparse container mount for reflection targets.
      kw.setdefault("makefile", "Makefile")
    return self._run(*args, **kw)


@pytest.fixture
def project(tmp_path, docker_cmk):
  """A `Project` scaffolded under tmp_path, driven via docker_cmk."""
  return Project(tmp_path, docker_cmk)


def _sweep_repo_tmp(before):
  # mk.interpret! runs from the repo, so io.mktemp drops `.tmp.*` in the repo
  # root. Remove the ones a run created (gitignored, but clutter otherwise).
  for p in set(REPO.glob(".tmp.*")) - before:
    try:
      p.unlink()
    except OSError:
      pass


@pytest.fixture(params=["vendored", "global"])
def run_demo(request, docker_cmk, tmp_path_factory):
  """Run any ``demos/cmk/*.cmk`` end-to-end, PARAMETRIZED over install mode, so
  every test using it yields two cases: ``...[vendored]`` and ``...[global]``.

  * ``vendored`` -- execute the repo's own ``./compose.mk`` (the default
    drop-in usage), via docker_cmk.
  * ``global``   -- stage a copy of compose.mk on a temp bin OUTSIDE the repo
    and execute THAT by absolute path, so CMK_SRC / dispatch exercise the
    global-install code paths. Scoped with the same docker label / compose
    project docker_cmk uses, so the session teardown sweeps anything it makes.

  Both run from the repo root (so a demo's ``demos/data/...`` + ``${PWD}``
  mounts resolve) with ``CMK_SUPERVISOR=1`` (the yield/interrupt epilogue needs
  it headless).
  """
  if request.param == "vendored":

    def run(relpath, timeout=600, **env):
      before = set(REPO.glob(".tmp.*"))
      try:
        return docker_cmk(
          "mk.interpret!",
          relpath,
          env={"CMK_SUPERVISOR": "1", **env},
          cwd=REPO,
          timeout=timeout,
        )
      finally:
        _sweep_repo_tmp(before)

    return run

  # global: a compose.mk on its own bin dir, OUTSIDE the repo workspace.
  prog = tmp_path_factory.mktemp("cmkbin") / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)

  def run(relpath, timeout=600, **env):
    merged = {
      **os.environ,
      **BASE_ENV,
      "CMK_SUPERVISOR": "1",
      "CMK_INTERNAL": "0",
      "docker_args": f"--label {CMKTEST_LABEL}",
      "DOCKER_HOST_WORKSPACE": str(REPO),
      "COMPOSE_PROJECT_NAME": COMPOSE_PROJECT,
      **env,
    }
    before = set(REPO.glob(".tmp.*"))
    proc = subprocess.Popen(
      [str(prog), "mk.interpret!", relpath],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      cwd=str(REPO),
      env=merged,
      start_new_session=True,
    )
    _LIVE_PROCS.add(proc)
    try:
      out, err = proc.communicate(input="", timeout=timeout)
    except subprocess.TimeoutExpired:
      _kill_proc_group(proc)
      out, err = proc.communicate()
      scoped_cleanup()
      raise
    finally:
      _LIVE_PROCS.discard(proc)
      _sweep_repo_tmp(before)
    return Result(out, err, proc.returncode)

  return run

  return run


# --- Gating + reporting hooks ----------------------------------------------


def pytest_collection_modifyitems(config, items):
  needs = [i for i in items if "needs_docker" in i.keywords]
  net = [i for i in items if "network" in i.keywords]
  if needs:
    docker_ok = _docker_available()
    disk_ok = docker_ok and _enough_disk()
    for item in needs:
      if not docker_ok:
        item.add_marker(pytest.mark.skip(reason="docker daemon not available"))
      elif not disk_ok:
        item.add_marker(
          pytest.mark.skip(reason=f"insufficient disk (<{MIN_DISK_GB}GB free)")
        )
  if net and os.environ.get("CMK_TEST_NETWORK") != "1":
    for item in net:
      item.add_marker(
        pytest.mark.skip(reason="network disabled (set CMK_TEST_NETWORK=1)")
      )
  nush = [i for i in items if "nushell" in i.keywords]
  if nush and os.environ.get("CMK_TEST_NUSHELL") != "1":
    for item in nush:
      item.add_marker(
        pytest.mark.skip(reason="nushell disabled (set CMK_TEST_NUSHELL=1)")
      )


def pytest_keyboard_interrupt(excinfo):
  for proc in list(_LIVE_PROCS):
    _kill_proc_group(proc)
  scoped_cleanup()


def pytest_sessionfinish(session, exitstatus):
  scoped_cleanup()


_SUITE_MARKERS = ("unit", "smoke", "docker", "integration", "compiler")


def pytest_runtest_logreport(report):
  # Record which suite markers actually executed (call phase, not skipped), so
  # smoke scripts are credited only when the smoke suite really ran.
  if report.when == "call" and not report.skipped:
    for mark in _SUITE_MARKERS:
      if mark in report.keywords:
        _RAN_SUITES.add(mark)


def pytest_terminal_summary(terminalreporter, exitstatus, config):
  # Report-only; opt-in so normal runs aren't noisy and a partial (e.g.
  # unit-only) run isn't misread as full coverage.
  if os.environ.get("CMK_TEST_COVERAGE") != "1":
    return
  try:
    exercised = set(_INVOKED_TARGETS)
    if "smoke" in _RAN_SUITES:
      for script in sorted(SCRIPTS_DIR.glob("*.sh")):
        exercised |= targets_in_script(script)
    denom = public_targets(COMPOSE_MK)
    gtext, gdata = generated_report(
      COMPOSE_MK, exercised, REPO / "tests" / "fixtures", denom
    )
    text, data = coverage_report(
      denom,
      exercised,
      _RAN_SUITES,
      mk_parse_targets(COMPOSE_MK),
      aliases=alias_map(COMPOSE_MK),
      extra_ns={
        "<generated>": (gdata["scored_total"], gdata["scored_covered"])
      },
    )
    terminalreporter.section("target coverage")
    terminalreporter.write_line(text)
    terminalreporter.section("generated target coverage")
    terminalreporter.write_line(gtext)
    data["generated"] = gdata
    # Key the artifacts to the suites that ran, so a partial run (e.g.
    # `-m integration`, with its low *library* totals) doesn't clobber the
    # full-run report. `make coverage` sets CMK_COVERAGE_LABEL=coverage so the
    # canonical run lands in a single `coverage.md`; ad-hoc runs get a
    # per-suite name like `coverage-integration.md`.
    label = os.environ.get("CMK_COVERAGE_LABEL")
    if not label:
      suites = "-".join(sorted(_RAN_SUITES)) or "none"
      label = f"coverage-{suites}"
    (REPO / "tests" / f".{label}.json").write_text(json.dumps(data, indent=2))
    (REPO / "tests" / f"{label}.md").write_text(coverage_markdown(data))
    terminalreporter.write_line(f"target coverage: wrote {label}.md")
  except Exception as exc:  # never let reporting fail the run
    terminalreporter.write_line(f"target coverage: report skipped ({exc})")


# Printed right after "collected N items", before the run starts.
def pytest_report_collectionfinish(config, items):
  suites = ("unit", "smoke", "docker", "integration", "compiler")
  gates = ("needs_docker", "network", "nushell")
  by_marker = Counter()
  by_file = Counter()
  for item in items:
    by_file[item.location[0]] += 1
    for mark in suites + gates:
      if mark in item.keywords:
        by_marker[mark] += 1
  markers = ", ".join(f"{k}={v}" for k, v in sorted(by_marker.items()))
  lines = [f"collection summary: {len(items)} tests ({markers})"]
  for path, count in sorted(by_file.items()):
    lines.append(f"  {path}: {count}")
  return lines
