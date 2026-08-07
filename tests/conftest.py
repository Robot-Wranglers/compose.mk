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
import re
import shutil
import signal
import subprocess
import tempfile
import uuid
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import pytest

from _targets import (
  alias_map,
  base_name,
  coverage_report,
  generated_report,
  mk_parse_targets,
  public_targets,
  targets_in_script,
)

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"
SCRIPTS_DIR = REPO / "tests" / "scripts"

# --- target-coverage recording (on by default; opt out with CMK_TEST_COVERAGE=0) ----
# Coverage is recorded per TEST NODE: each test's slice is the set of target
# base-names it invoked via the fixtures.  At session end each ran test's slice
# is REPLACED (not unioned) in the canonical JSON and untouched tests are kept,
# so any subset run -- a single `pytest -k` included -- refreshes exactly its own
# tests and a stale credit self-corrects the next time that test runs.
_INVOKED_TARGETS: set = set()  # session union (printed summary only)
_RAN_SUITES: set = set()
# nodeids whose call phase actually executed (not skipped/deselected) -- only these
# get their slice REPLACED; a skipped test keeps its prior slice (it measured nothing).
_RAN_TESTS: set = set()
# nodeid -> set of invoked base-names, for this session's ran tests.
_PER_TEST: dict = {}
# The test currently executing (set by the runtest hookwrapper), so fixture
# invocations attribute to the right slice; None between tests.
_CURRENT_NODEID = None
# Every nodeid pytest COLLECTED this session (pre-deselection), i.e. the files in
# scope of this run -- used to prune slices of deleted/renamed tests without
# dropping tests that were merely out of scope.
_COLLECTED_NODEIDS: set = set()


def _record_invoked(name):
  # Credit a target to the session union and to the current test's slice.
  _INVOKED_TARGETS.add(name)
  _PER_TEST.setdefault(_CURRENT_NODEID or "__session__", set()).add(name)

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
# Selectively neutralize an inherited `-w`/print-directory (e.g. when the whole test
# run is itself launched from a `make` target, which exports MAKEFLAGS=w/MAKELEVEL):
# APPEND `--no-print-directory` to the inherited MAKEFLAGS (last-wins overrides `-w`,
# preserves the user's other flags) rather than clobbering it.  Keeps `Entering/Leaving
# directory` out of captured stdout for the `make -f wrapper` (include-path) tests.
BASE_ENV["MAKEFLAGS"] = (
  os.environ.get("MAKEFLAGS", "") + " --no-print-directory"
).strip()


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
  ``./.tmp.*`` and ``.stage.*``) land in the temp dir and never pollute
  the repo; pytest removes the dir afterwards.
  """

  def run(
    *args, stdin="", env=None, cwd=None, makefile=None, timeout=None
  ) -> Result:
    if args:
      _record_invoked(base_name(args[0]))
    merged = {**os.environ, **BASE_ENV, **(env or {})}
    # A wrapper makefile (which `include`s compose.mk) lets a test supply its
    # own defs/targets, e.g. a `define` for mk.def.read.
    argv = (
      ["make", "-f", str(makefile), *args]
      if makefile
      else [str(COMPOSE_MK), *args]
    )
    # `timeout` (seconds) bounds the run so a pathological hang (e.g. an import
    # cycle that lost its guard) fails the test instead of stalling the suite.
    proc = subprocess.run(
      argv,
      input=stdin,
      text=True,
      errors="replace",
      capture_output=True,
      cwd=str(cwd or tmp_path),
      env=merged,
      timeout=timeout,
    )
    return Result(proc.stdout, proc.stderr, proc.returncode)

  return run


def _balanced(text, prefix):
  """Every `$(<kw> ..)` invocation in ``text`` for ``prefix`` == ``$(<kw> ``, as
  full paren-balanced strings.  Used to pull `$(call ..)` / `$(error ..)` out of
  lowered output where the args themselves carry nested parens (e.g. `*(| .. |)`)."""
  out, i = [], 0
  while True:
    k = text.find(prefix, i)
    if k < 0:
      return out
    depth, j = 0, k + 1  # start at the opening '(' of `$(`
    while j < len(text):
      if text[j] == "(":
        depth += 1
      elif text[j] == ")":
        depth -= 1
        if depth == 0:
          break
      j += 1
    out.append(text[k : j + 1])
    i = j + 1


class IR(str):
  """The lowered CMK->Makefile text (``mk.compile`` stdout), with structured views.

  It IS the compiled string (subclasses ``str``), so the legacy substring style
  keeps working verbatim -- ``"define X" in ir``, ``ir.split("endef")``,
  ``ir.count(..)``.  It also carries the run's ``.stdout``/``.stderr``/
  ``.returncode``/``.ok`` (so a helper that returned the raw ``Result`` migrates
  unchanged), plus parsed accessors so assertions can target the LOWERING's
  structure instead of raw text:

      ir = ir_compile("X := (| a:; cmk.log(hi) |)\\n")
      ir.define("X")                 # body between `define X` .. `endef` (or None)
      ir.defines()                   # ["X"] -- every define-block name
      ir.calls("log")         # ["$(call log,hi)"]  (paren-balanced)
      ir.calls()                     # every `$(call ..)` invocation
      ir.rule("a")                   # recipe text for target `a:` (inline or tabbed)
      ir.error()                     # the `$(error ..)` message, or None
      ir.body                        # text minus the shebang/context-header preamble
  """

  def __new__(cls, text, stderr="", returncode=0):
    obj = super().__new__(cls, text)
    obj.stdout = text
    obj.stderr = stderr
    obj.returncode = returncode
    return obj

  @property
  def ok(self) -> bool:
    return self.returncode == 0

  @property
  def body(self) -> str:
    """The lowering with the shebang + ``MAKEFILE_LIST`` + ``# generated from
    context:`` comment preamble stripped -- just the emitted statements."""
    marker = "# generated from context:"
    if marker not in self:
      return str(self)
    lines = str(self).split(marker, 1)[1].splitlines()
    j = 0  # skip the JSON comment block + trailing blanks that follow the marker
    while j < len(lines) and (lines[j].startswith("#") or not lines[j].strip()):
      j += 1
    return "\n".join(lines[j:])

  def _blocks(self) -> dict:
    blocks, lines, i = {}, str(self).splitlines(), 0
    while i < len(lines):
      m = re.match(r"define (\S+)\s*$", lines[i])
      if m:
        j, buf = i + 1, []
        while j < len(lines) and lines[j].rstrip() != "endef":
          buf.append(lines[j])
          j += 1
        blocks.setdefault(m.group(1), "\n".join(buf))
        i = j + 1
      else:
        i += 1
    return blocks

  def define(self, name):
    """The verbatim body between ``define <name>`` and ``endef`` (first block of
    that name), or None if there is no such block."""
    return self._blocks().get(name)

  def defines(self) -> list:
    """Every ``define`` block name, in source order."""
    names, seen = [], set()
    for line in str(self).splitlines():
      m = re.match(r"define (\S+)\s*$", line)
      if m and m.group(1) not in seen:
        seen.add(m.group(1))
        names.append(m.group(1))
    return names

  def calls(self, name=None) -> list:
    """Every ``$(call ..)`` invocation (paren-balanced full strings).  With
    ``name``, only calls whose target is exactly ``name`` (`$(call name,..)` /
    `$(call name)`)."""
    got = _balanced(str(self), "$(call ")
    if name is None:
      return got
    pat = re.compile(r"\$\(call " + re.escape(name) + r"\s*[,)]")
    return [c for c in got if pat.match(c)]

  def error(self):
    """The message of the emitted ``$(error ..)`` (first one), or None."""
    got = _balanced(str(self), "$(error ")
    return got[0][len("$(error ") : -1] if got else None

  def rule(self, target):
    """The recipe text for ``<target>:`` -- an inline ``t:; cmd`` or the tabbed
    recipe lines (de-tabbed, newline-joined) -- or None if no such rule."""
    lines = str(self).splitlines()
    head = re.compile(r"^" + re.escape(target) + r"\s*:")
    for idx, line in enumerate(lines):
      if not head.match(line):
        continue
      rhs = line.split(":", 1)[1]
      recipe = []
      if rhs.lstrip().startswith(";"):
        recipe.append(rhs.lstrip()[1:].strip())
      j = idx + 1
      while j < len(lines) and lines[j].startswith("\t"):
        recipe.append(lines[j][1:])
        j += 1
      return "\n".join(recipe)
    return None


@pytest.fixture
def ir(cmk):
  """Compile CMK-lang to Makefile IR and return an ``IR`` handle for asserting on
  the LOWERING (fast, pure ``mk.compile`` -- no docker).  Replaces the ~9
  hand-copied ``def _c(cmk, src)`` compile helpers across the suite.

      def test_lowers(ir):
          out = ir("x:\\n\\tthis.y\\n")
          assert "${make} y" in out            # substring style still works
          assert out.calls("log") == [] # ...or assert on structure

  By default the compile is asserted to succeed (matching every ``_c``); pass
  ``ok=False`` for a failure-path test (no assert, inspect ``.ok``/``.stderr``).
  ``wrap=True`` wraps ``src`` as the recipe of a throwaway ``x:`` target, and
  ``decl`` prepends declaration lines -- the ``{decl}x:\\n\\t{body}`` idiom the
  receiver/fluent suites used.  Compiler env vars pass either as an ``env=``
  dict (matching the raw ``cmk(...)`` call it replaces) or as bare kwargs."""

  def compile(src, *, decl="", wrap=False, ok=True, env=None, **env_kw):
    stdin = f"{decl}x:\n\t{src}\n" if wrap else f"{decl}{src}"
    merged = {**(env or {}), **env_kw}
    r = cmk("mk.compile", stdin=stdin, env=merged or None)
    if ok:
      assert r.ok, r.stderr
    return IR(r.stdout, r.stderr, r.returncode)

  return compile


@dataclass
class SandboxResult:
  """Outcome of one sandbox injection: the target run PLUS the transpiled cache text."""

  stdout: str
  stderr: str
  returncode: int
  compiled: str | None  # the transpiled sandbox cache, or None if the build failed/was skipped

  @property
  def ok(self) -> bool:
    return self.returncode == 0

  @property
  def output(self) -> str:
    return self.stdout + self.stderr


@pytest.fixture
def sandbox(cmk, tmp_path):
  """Inject arbitrary CMK-lang as the FULL `__sandbox__` body and drive it through the REAL
  hosted-partition compiler, per test.  A safe bench for the recurring dedent/cook/docstring
  hazards -- experimental content rides the actual `lang.transpile` pipeline without touching the
  load-bearing `__hosted__` partition (see `CMK_SANDBOX_SRC` in compose.mk's sandbox staging).

  The returned harness has two entry points, both returning a ``SandboxResult`` whose ``compiled``
  attribute is the LOWERED makefile text (assert on how the compiler transformed your snippet):

      def test_run(sandbox):                      # inject + RUN a target, assert on behavior
          r = sandbox.run("probe:\\n\\t@echo hi", goal="probe")
          assert r.ok and "hi" in r.stdout

      def test_lowering(sandbox):                 # inject + COMPILE only, assert on lowered output
          r = sandbox.compile("probe:\\n  '''doc'''\\n  echo hi")
          assert "@# doc" in r.compiled           # a target docstring lowers to an `@#` comment

      def test_broken(sandbox):                   # a bad snippet is non-fatal: compiled is None
          r = sandbox.compile("busted(|\\n  '''unterminated")
          assert r.compiled is None and "cmk:" in r.stderr

  Notes: the body is col-0 CMK-lang (exactly what `lang.transpile` sees after the in-file body's
  2-space strip), so recipes use a literal tab.  Each body is content-addressed to its own cache
  under a hermetic ``tmp_path/.cmk``.  Injection auto-activates the sandbox (no `CMK_SANDBOX` needed).
  """
  cmk_dir = tmp_path / ".cmk"
  cmk_dir.mkdir(exist_ok=True)
  wrapper = tmp_path / "Makefile"
  wrapper.write_text("include %s\n" % COMPOSE_MK)
  src = tmp_path / "sandbox_body.cmk"

  def _caches():
    return sorted(cmk_dir.glob(".tmp.sandbox.*.mk"))

  def _drive(body, goal, env):
    for stale in _caches():  # fresh, content-addressed cache per injected body
      stale.unlink()
    src.write_text(body if body.endswith("\n") else body + "\n")
    r = cmk(
      goal,
      makefile=wrapper,
      cwd=tmp_path,
      env={"CMK_SANDBOX_SRC": str(src), **env},
    )
    built = _caches()
    compiled = built[0].read_text() if built else None
    return SandboxResult(r.stdout, r.stderr, r.returncode, compiled)

  class Harness:
    def run(self, body, goal="probe", **env):
      """Inject ``body`` as the sandbox, run ``goal`` (default ``probe``), return SandboxResult."""
      return _drive(body, goal, env)

    def compile(self, body, **env):
      """Inject ``body`` and build the cache only (via ``mk.sandbox.prewarm``); ``.compiled`` is
      the transpiled text, or None if the build failed (a bad snippet warns + skips, non-fatal).

      A sentinel target is appended so a TARGET-LESS body (a bare class / banana form) still
      produces a promotable cache -- the ">= 1 target" gate would otherwise reject it.  The
      injected content's lowering is intact above the sentinel; assert on your own substring."""
      if not body.endswith("\n"):
        body += "\n"
      body += "_cmk_sandbox_sentinel:\n\t@true\n"
      return _drive(body, "mk.sandbox.prewarm", env)

  return Harness()


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
      errors="replace",
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
  exclusively ours, so this is safe - but it assumes no *concurrent* harness
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
      errors="replace",
    ).stdout.split()
    _rm(["docker", "network", "rm"], [n for n in names if "cmktest" in n])
  except Exception:
    pass
  if os.environ.get("CMK_TEST_KEEP_IMAGES") != "1":
    _rm(["docker", "rmi", "-f"], _docker_ids("images", "cmktest"))


@pytest.fixture(scope="session", autouse=True)
def _hosted_encapsulation_gate():
  """FAIL-FAST GATE for EVERY suite (root-conftest session-autouse, so it runs once up
  front no matter which markers/files are selected).  The __hosted__ partition is authored
  in CMK-lang and leans on the `*(| .. |)` encapsulate/expand idiom -- an inline anonymous
  module dissolved in place (e.g. the io.* leaf group).  If that idiom breaks, the hosted
  cache won't build and EVERY test that shells out to compose.mk fails confusingly.  So we
  compile+run the idiom in isolation ONCE (which also loads the real hosted cache) and abort
  the whole session immediately if it's broken, rather than reporting a storm of downstream
  failures.  Uses a clean `cmk run <file>` (not BASE_ENV, whose CMK_SUPERVISOR=0/MAKEFLAGS
  tweaks are for capture-determinism and would divert `cmk run` into transpile)."""
  src = '*(|\n  hosted.gate/%:; @printf "GATE:%s" "${*}"\n|)\n__main__: hosted.gate/ok\n'
  with tempfile.NamedTemporaryFile("w", suffix=".cmk", delete=False) as f:
    f.write(src)
    path = f.name
  try:
    r = subprocess.run(
      [str(COMPOSE_MK), "cmk", "run", path],
      cwd=str(REPO),
      stdin=subprocess.DEVNULL,
      text=True,
      capture_output=True,
      env={**os.environ, "CMK_INTERNAL": "1", "CMK_COMPILER_VERBOSE": "0", "NO_COLOR": "1"},
      timeout=120,
    )
  finally:
    os.unlink(path)
  if "GATE:ok" not in (r.stdout + r.stderr):
    pytest.exit(
      "FATAL: the `*(| .. |)` encapsulate/expand idiom is broken -- the __hosted__ "
      "partition is trashed, aborting ALL suites.\n"
      f"--- stdout ---\n{r.stdout}\n--- stderr ---\n{r.stderr}",
      returncode=1,
    )
  yield


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
      _record_invoked(base_name(args[0]))
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
      errors="replace",
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
      errors="replace",
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


@pytest.fixture
def staged_global(tmp_path_factory):
  """Run an ARBITRARY compose.mk target from a GLOBAL install: a copy of
  compose.mk on its own bin dir OUTSIDE any workspace, executed by absolute path
  with an empty workspace as ${PWD}/DOCKER_HOST_WORKSPACE. This forces cmk.self /
  docker.cmk.mount / makefile_list.dind down their global-install branches (so the
  in-container command references the /usr/local/bin/compose.mk mount, not the
  host path). Scoped with the session docker label + compose project so teardown
  sweeps anything it makes; container runs use --rm so most cleans up itself.
  """
  prog = tmp_path_factory.mktemp("cmkbin") / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  ws = tmp_path_factory.mktemp("cmkws")  # empty workspace (no vendored copy)

  def run(*args, timeout=1800, **env):
    merged = {
      **os.environ,
      **BASE_ENV,
      "CMK_SUPERVISOR": "1",
      "CMK_INTERNAL": "0",
      "docker_args": f"--label {CMKTEST_LABEL}",
      "DOCKER_HOST_WORKSPACE": str(ws),
      "COMPOSE_PROJECT_NAME": COMPOSE_PROJECT,
      **env,
    }
    proc = subprocess.Popen(
      [str(prog), *args],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
      errors="replace",
      cwd=str(ws),
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
    return Result(out, err, proc.returncode)

  # expose the staged paths so callers can run artifacts the target produced
  # (e.g. a packaged binary lands in the workspace).
  run.workspace = ws
  run.prog = prog
  return run


@pytest.fixture
def tui():
  """Run a tux/loadf TUI entrypoint HEADLESSLY from the repo root.

  Interactive TUI flows end by attaching to tmux, which needs a real TTY. Run
  headless we close stdin and time-box the process, then assert on the tmuxp
  *load* markers in the (merged stdout+stderr) output -- NOT the exit code, since
  the final `tmux attach` always fails without a tty. compose.mk is invoked by
  the RELATIVE `./compose.mk` (cwd = repo) so the in-container `make -f` paths
  resolve via the /workspace mount. CMK_SUPERVISOR=1 because loadf/tux.* use
  `mk.yield`. Scoped with the session docker label + compose project so teardown
  sweeps the tux containers/volumes/networks; repo `.tmp.*` are swept too.
  """

  def run(*args, timeout=600, **env):
    before = set(REPO.glob(".tmp.*"))
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
    proc = subprocess.Popen(
      ["./compose.mk", *args],
      stdin=subprocess.DEVNULL,
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT,
      text=True,
      errors="replace",
      cwd=str(REPO),
      env=merged,
      start_new_session=True,
    )
    _LIVE_PROCS.add(proc)
    try:
      out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
      _kill_proc_group(proc)
      out, _ = proc.communicate()
      scoped_cleanup()
      raise
    finally:
      _LIVE_PROCS.discard(proc)
      _sweep_repo_tmp(before)
    return Result(out, "", proc.returncode)

  return run


@pytest.fixture
def run_plain_demo(docker_cmk):
  """Run a plain ``demos/*.mk`` Makefile directly -- NOT via ``mk.interpret!``
  (that path is only for ``demos/cmk/*.cmk``). Executes ``make -f
  demos/<name>.mk <target>`` from the repo root (so ``include compose.mk`` and
  ``demos/data/*`` resolve), via docker_cmk so any container a demo dispatches is
  label-scoped and swept. Default target is ``__main__`` (the demo entrypoint
  convention). Runs under the deterministic BASE_ENV (CMK_SUPERVISOR=0 + hooks
  off) -- the same plain ``make -f`` path the demos' shebang uses. Not
  parametrized vendored/global: these demos use a literal ``include compose.mk``,
  so only the vendored path applies.

  The makefile is passed as a repo-relative path (cwd is the repo root) so demos
  that reflect/dispatch -- which re-run ``make -f ${MAKEFILE}`` inside the
  workspace mount -- see a path valid in-container (cf. the Project fixture).
  """

  def run(relpath, *targets, timeout=300, **env):
    before = set(REPO.glob(".tmp.*"))
    try:
      return docker_cmk(
        *(targets or ("__main__",)),
        makefile=relpath,
        cwd=REPO,
        env=env or None,
        timeout=timeout,
      )
    finally:
      _sweep_repo_tmp(before)

  return run


# --- Gating + reporting hooks ----------------------------------------------

# Topical auto-labeling: a test whose NODEID (file::name) contains a subsystem token
# gets that TOPIC marker automatically, so `-m <topic>` stays complete without anyone
# remembering to decorate each new test. Labels are free; forgetting to apply them was
# the gate blind spot that let regressions ship. Test FILES are already subsystem-named,
# so a substring match on the nodeid is high-precision. Explicit `@pytest.mark.<topic>`
# still stands (documents intent + covers names a substring misses). TOPICS are the
# subject axis and cross-cut the capability SUITES (unit/docker/..); every topic here is
# also registered in pytest.ini (strict-markers). Substrings are chosen to avoid
# `docker` (never matches `doc*`) and other cross-hits; verify with the per-topic counts.
_TOPIC_NODE_SUBSTRINGS = {
  "docstring": ("docstring", "moduledoc", "targetdoc", "target_doc", "doc_accessor", "__doc__"),
  "self": ("self",),
  "banana": ("banana",),
  "namespace": ("namespace",),
  "module": ("module",),
  "vm": ("vm_", "::vm", "/vm.", "vm.py", "vm_cmk"),
  "machine": ("machine",),
  "protocol": ("protocol",),
  "classvar": ("classvar",),
  "class_system": ("class_", "class.", "inheritance", "dot_operator"),
  "callform": ("callform",),
  "receiver": ("receiver",),
  "import": ("import", "include"),
  "sandbox": ("sandbox",),
  "hosted": ("hosted",),
  "channel": ("channel",),
  "code_object": ("code_object",),
  "dsl": ("dsl",),
  "jqlang": ("jqlang",),
  "awklang": ("awklang",),
  "polyglot": ("polyglot",),
  "repl": ("repl",),
  "m5": ("m5_", "m5.", "mtable", "m5table"),
  "ambient": ("ambient",),
  "pragma": ("pragma",),
  "bootloader": ("bootloader", "pragma_boot", "boot.py"),
  "stack": ("stack",),
  "overlay": ("overlay",),
  "completion": ("completion",),
  "reflection": ("reflect",),
  "lambda": ("lambda",),
  "kwargs": ("kwarg",),
  "ctor": ("ctor", "instance_new"),
  "iface": ("iface",),
  "fault": ("_fault", "errno", "mk_error"),  # NOT 'fault'/'fault_' -- both hit 'default'/'default_'
  "flux": ("flux",),
  "metaprogramming": ("metaprogram",),
  "cmklang": ("cmklang", "cmk_lang"),
  "supervisor": ("super_once", "supervisor", "signals"),
  # --- discovered from uncovered test files + recurring memory subsystems ---
  "compiler": ("compiler", "tower", "transpile", "lowers", "lowering", "minify", "joinbody"),
  "cook": ("cook",),
  "goals": ("goals_cmk", "backtrack", "queens"),
  "trampoline": ("tramp", "beam"),
  "hooks": ("hook",),
  "glob": ("intermediate_glob", "globbing"),  # NOT bare 'glob'/'_glob' -- hits 'global'
  "logging": ("loggable", "logger", "logging"),
  "capture": ("capture",),
  "tools": ("tool",),
  "streams": ("stream",),
  "entrypoint": ("entrypoint", "__main__", "has_main", "main_callable"),
  "dockerfile": ("dockerfile",),
  "compose": ("unit_compose", "compose_machine", "integration_compose", "composefile"),
  "seed": ("seed",),
  "feed": ("feed",),
}


@pytest.hookimpl(tryfirst=True)
def pytest_collection_modifyitems(config, items):
  # tryfirst so we snapshot the collected universe BEFORE any -k/-m (or our own)
  # deselection removes items -- `items` is then everything pytest collected for
  # this invocation's path args, letting the coverage prune tell "test deleted"
  # (file in scope, node gone) from "test out of scope" (file not collected) and
  # from "test merely -k-filtered" (still in the snapshot).
  _COLLECTED_NODEIDS.update(i.nodeid for i in items)
  for item in items:
    nid = item.nodeid.lower()
    for _topic, _subs in _TOPIC_NODE_SUBSTRINGS.items():
      if any(s in nid for s in _subs):
        item.add_marker(getattr(pytest.mark, _topic))
    # CONTENT-based: a test using the `ir` compile-IR fixture asserts on lowered
    # output -> it IS a compiler test, regardless of its name. (`sandbox` is mixed
    # compile+run, so it is NOT auto-compiler; those files tag explicitly.)
    if "ir" in getattr(item, "fixturenames", ()):
      item.add_marker(pytest.mark.compiler)
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
  tui = [i for i in items if "tui" in i.keywords]
  if tui and os.environ.get("CMK_TEST_TUI") != "1":
    for item in tui:
      item.add_marker(
        pytest.mark.skip(reason="tui disabled (set CMK_TEST_TUI=1)")
      )
  awkm = [i for i in items if "awk_matrix" in i.keywords]
  if awkm and os.environ.get("CMK_TEST_AWK_MATRIX") != "1":
    for item in awkm:
      item.add_marker(
        pytest.mark.skip(reason="awk matrix disabled (set CMK_TEST_AWK_MATRIX=1)")
      )
  nb = [i for i in items if "notebooking" in i.keywords]
  if nb and os.environ.get("CMK_TEST_NOTEBOOKING") != "1":
    for item in nb:
      item.add_marker(
        pytest.mark.skip(reason="notebooking disabled (set CMK_TEST_NOTEBOOKING=1)")
      )


def pytest_keyboard_interrupt(excinfo):
  for proc in list(_LIVE_PROCS):
    _kill_proc_group(proc)
  scoped_cleanup()


def pytest_sessionfinish(session, exitstatus):
  scoped_cleanup()


_SUITE_MARKERS = (
  "unit",
  "plugin",
  "smoke",
  "docker",
  "integration",
  "compiler",
)


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_protocol(item, nextitem):
  # Bracket each test so fixture target-invocations attribute to its slice.  We do
  # NOT pre-seed the slice here (that would give a SKIPPED test an empty slice and
  # wipe its prior coverage); the slice is created only when a target is actually
  # invoked, and only ran tests get their slice replaced (see _RAN_TESTS below).
  global _CURRENT_NODEID
  _CURRENT_NODEID = item.nodeid
  try:
    yield
  finally:
    _CURRENT_NODEID = None


def pytest_runtest_logreport(report):
  # A test's call phase actually executed (not skipped) -- credit its suite marker
  # (so smoke scripts count only when smoke ran) and mark it as a "ran" test whose
  # slice may be replaced.
  if report.when == "call" and not report.skipped:
    _RAN_TESTS.add(report.nodeid)
    for mark in _SUITE_MARKERS:
      if mark in report.keywords:
        _RAN_SUITES.add(mark)


def pytest_terminal_summary(terminalreporter, exitstatus, config):
  # Recording is ON by default (opt out with CMK_TEST_COVERAGE=0).  The write is
  # cheap; the human summary is printed only when opted IN (CMK_TEST_COVERAGE=1),
  # so normal runs stay quiet.
  if os.environ.get("CMK_TEST_COVERAGE") == "0":
    return
  verbose = os.environ.get("CMK_TEST_COVERAGE") == "1"
  # Nothing actually executed (collect-only / all skipped / no match) -> leave the
  # file untouched rather than rewrite it from an empty session.
  if not _RAN_TESTS:
    return
  try:
    # Smoke scripts are a synthetic slice, refreshed only when the smoke suite ran.
    if "smoke" in _RAN_SUITES:
      smoke = set()
      for script in sorted(SCRIPTS_DIR.glob("*.sh")):
        smoke |= targets_in_script(script)
      _PER_TEST["__smoke_scripts__"] = smoke

    label = os.environ.get("CMK_COVERAGE_LABEL", "coverage")
    path = REPO / "tests" / f".{label}.json"
    prior = {}
    if path.exists() and os.environ.get("CMK_COVERAGE_RESET") != "1":
      try:
        prior = json.loads(path.read_text())
      except (ValueError, OSError):
        prior = {}

    # Per-test slices: REPLACE the slice of every test that actually RAN this
    # session (empty if it invoked nothing, retracting stale credit), and KEEP the
    # rest.  Any subset run (a single `pytest -k` included) refreshes exactly its
    # own tests; a stale credit self-corrects the next time that test runs.  The
    # synthetic "__session__" slice (targets invoked outside any test) is refreshed
    # whenever it was produced.
    slices = {nid: list(v) for nid, v in prior.get("slices", {}).items()}
    for nid in _RAN_TESTS:
      slices[nid] = sorted(_PER_TEST.get(nid, set()))
    if "__session__" in _PER_TEST:
      slices["__session__"] = sorted(_PER_TEST["__session__"])

    # Prune deleted/renamed tests: a prior slice whose FILE was collected in FULL
    # this run (so every live sibling was scanned) but whose nodeid is gone.
    # `_COLLECTED_NODEIDS` is captured pre-deselection, so a merely -k/-m-filtered
    # test is NOT pruned.  A file pinned at nodeid granularity (`file::test` in the
    # path args) collected only that node, so it is EXCLUDED from prune scope --
    # else running one test would wrongly evict its siblings.  Synthetic "__*"
    # slices are exempt; a whole deleted FILE is out of scope and clears on reset.
    pinned_files = {
      a.split("::", 1)[0] for a in getattr(config, "args", []) if "::" in a
    }
    scoped_files = {
      nid.split("::", 1)[0] for nid in _COLLECTED_NODEIDS
    } - pinned_files
    for nid in list(slices):
      if nid.startswith("__") or nid in _COLLECTED_NODEIDS:
        continue
      if nid.split("::", 1)[0] in scoped_files:
        del slices[nid]

    invoked = set().union(*(set(v) for v in slices.values())) if slices else set()
    suites = sorted(set(prior.get("suites_run", [])) | set(_RAN_SUITES))
    denom = public_targets(COMPOSE_MK)

    gtext, gdata = generated_report(
      COMPOSE_MK, invoked, REPO / "tests" / "fixtures", denom
    )
    # The mk.parse cross-check spawns a subprocess -- skip it on the default
    # every-run path; run it only when explicitly requested (canonical pass).
    mkparse = (
      mk_parse_targets(COMPOSE_MK)
      if os.environ.get("CMK_COVERAGE_MKPARSE") == "1"
      else None
    )
    text, data = coverage_report(
      denom,
      invoked,
      suites,
      mkparse,
      aliases=alias_map(COMPOSE_MK),
      extra_ns={
        "<generated>": (gdata["scored_total"], gdata["scored_covered"])
      },
    )
    data["generated"] = gdata
    data["slices"] = {nid: slices[nid] for nid in sorted(slices)}
    data["invoked_all"] = sorted(invoked)  # derived; kept for back-compat
    # The JSON is the canonical artifact; the human-readable summary is a view
    # rendered from it on demand (tests/coverage.md.j2, and the docs stats page).
    path.write_text(json.dumps(data, indent=2))

    # What THIS run changed, as JSON: which test slices were added/updated/pruned
    # and which core targets flipped covered<->uncovered.  Handy for ad-hoc runs
    # (`CMK_COVERAGE_DELTA=1 pytest -k foo`); also written to `.{label}.delta.json`.
    if os.environ.get("CMK_COVERAGE_DELTA") == "1":
      prior_slices = prior.get("slices", {})
      updated = {}
      for nid in set(prior_slices) & set(data["slices"]):
        was, now = set(prior_slices[nid]), set(data["slices"][nid])
        if was != now:
          updated[nid] = {"+": sorted(now - was), "-": sorted(was - now)}
      pc, nc = set(prior.get("covered_targets", [])), set(data["covered_targets"])
      delta = {
        "ran_tests": len(_RAN_TESTS),
        "suites": sorted(_RAN_SUITES),
        "slices": {
          "added": sorted(set(data["slices"]) - set(prior_slices)),
          "updated": updated,
          "pruned": sorted(set(prior_slices) - set(data["slices"])),
        },
        "covered": {"+": sorted(nc - pc), "-": sorted(pc - nc)},
        "percent": {"before": prior.get("percent"), "after": data["percent"]},
      }
      (REPO / "tests" / f".{label}.delta.json").write_text(
        json.dumps(delta, indent=2)
      )
      terminalreporter.section("target coverage delta")
      terminalreporter.write_line(json.dumps(delta, indent=2))

    if verbose:
      terminalreporter.section("target coverage (per-test slices)")
      terminalreporter.write_line(text)
      terminalreporter.section("generated target coverage")
      terminalreporter.write_line(gtext)
      terminalreporter.write_line(f"target coverage: merged into .{label}.json")
  except Exception as exc:  # never let reporting fail the run
    if verbose:
      terminalreporter.write_line(f"target coverage: report skipped ({exc})")


# Printed right after "collected N items", before the run starts.
def pytest_report_collectionfinish(config, items):
  suites = ("unit", "smoke", "docker", "integration", "compiler")
  gates = ("needs_docker", "network", "nushell", "tui")
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
