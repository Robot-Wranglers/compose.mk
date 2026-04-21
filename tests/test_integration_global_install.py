"""Global / on-PATH compose.mk (ADDITIVE option; vendored stays the default).

A project uses `include $(shell which compose.mk)` with NO vendored copy in the
tree -- compose.mk is staged on PATH instead. Two things must work:

1. host/library mode: stdlib targets run, and CMK_SRC resolves to the global
   absolute path.
2. container dispatch: `compose.import`-generated dispatch works because the
   mirror-mount binds the host compose.mk at /usr/local/bin/compose.mk inside
   the container (so the container-side `$(shell which compose.mk)` resolves to
   the identical file). The mount is gated to compose.mk-outside-the-workspace,
   so vendored/drop-in dispatch (covered by the rest of the suite) is unchanged.
"""

import os
import shutil
import signal
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

# Guarded include idiom: fail loudly if compose.mk isn't on PATH.
GUARDED_INCLUDE = (
  "_cmk := $(shell which compose.mk)\n"
  "$(if $(_cmk),,$(error compose.mk not on PATH))\n"
  "include $(_cmk)\n"
)


@pytest.fixture
def global_bin(tmp_path_factory):
  """A PATH dir holding compose.mk, OUTSIDE any project workspace (so the
  dispatch mirror-mount engages)."""
  d = tmp_path_factory.mktemp("cmkbin")
  dest = d / "compose.mk"
  shutil.copy(COMPOSE_MK, dest)
  dest.chmod(0o755)
  return d


@pytest.mark.integration
def test_global_install_host_target(cmk, tmp_path, global_bin):
  # Library mode via a global include, no local copy: a stdlib target runs and
  # CMK_SRC resolves to the staged global absolute path.
  (tmp_path / "Makefile").write_text(
    GUARDED_INCLUDE
    + "selfcheck:; @echo cmk=$(CMK_SRC); echo abc | $(make) stream.echo\n"
  )
  env = {"PATH": f"{global_bin}:{os.environ['PATH']}"}
  r = cmk("selfcheck", makefile=tmp_path / "Makefile", cwd=tmp_path, env=env)
  assert r.ok, r.stderr
  assert "abc" in r.stdout  # stdlib (stream.echo) works through the include
  assert str(global_bin) in r.stdout  # CMK_SRC -> global abspath


@pytest.mark.integration
@pytest.mark.needs_docker
def test_global_install_container_dispatch(docker_cmk, tmp_path, global_bin):
  # Dispatch a make target into a compose service under a global install. The
  # mirror-mount makes compose.mk reachable in-container so the re-run's
  # `include $(shell which compose.mk)` resolves.
  #
  # The service name must be UNIQUE across the suite: a `build:.` service with no
  # explicit `image:` is tagged by compose as `<project>-<service>`, and the whole
  # session shares one COMPOSE_PROJECT_NAME. A generic name (e.g. `appsvc`, also
  # used by the make-less `compose-import-app` fixture) collides on that tag, so
  # `<svc>.dispatch` would reuse whichever image built first -> `make: not found`.
  (tmp_path / "Dockerfile").write_text(
    "FROM alpine:3.21.2\nRUN apk add --no-cache make bash coreutils\n"
  )
  (tmp_path / "dc.yml").write_text(
    "services:\n"
    "  gidispatchsvc:\n"
    "    build: .\n"
    "    working_dir: /workspace\n"
    "    volumes:\n"
    "      - ${DOCKER_HOST_WORKSPACE:-${PWD}}:/workspace\n"
  )
  (tmp_path / "Makefile").write_text(
    GUARDED_INCLUDE
    + "$(call compose.import, file=dc.yml)\n"
    + "incontainer:; @echo IN-CONTAINER-OK host=$$(hostname)\n"
  )
  env = {"PATH": f"{global_bin}:{os.environ['PATH']}"}
  r = docker_cmk(
    "gidispatchsvc.dispatch/incontainer",
    makefile="Makefile",
    cwd=tmp_path,
    env=env,
    timeout=400,
  )
  assert r.ok, r.stderr
  assert "IN-CONTAINER-OK" in r.stdout


# --- CMK compile / interpret under global install (the tangled path) ---------
# Differential characterization. CMK has two run modes:
#   * TOOL mode:    `compose.mk mk.interpret! file.cmk` (CMK_STANDALONE) ->
#                   CMK_SRC := $(findstring compose.mk, MAKE_CLI) == bare
#                   "compose.mk" (compose.mk:357), and mk.interpret does
#                   `cat ${CMK_SRC}` (compose.mk:2280) to inline the stdlib.
#   * LIBRARY mode: project `include $(shell which compose.mk)` then
#                   `$(make) mk.interpret!` (CMK_LIB) -> CMK_SRC is the absolute
#                   include path via $(filter %compose.mk,MAKEFILE_LIST) (:339).
# Vendored tool-mode works (./compose.mk is in CWD). GLOBAL tool-mode breaks
# because bare "compose.mk" doesn't exist in CWD. Library mode is fine.

CHAIN = "a:\n\tprintf one\nb:\n\tprintf two\n__main__:\n\tthis.a; this.b\n"


def _staged_env(global_bin, supervisor="1"):
  return {
    **os.environ,
    "NO_COLOR": "1",
    "CMK_DISABLE_HOOKS": "1",
    "TERM": "dumb",
    "TRACE": "0",
    "GITHUB_ACTIONS": "false",
    "CMK_SUPERVISOR": supervisor,  # mk.interpret! needs the supervisor headless
    "PATH": f"{global_bin}:{os.environ['PATH']}",
  }


def _run(argv, cwd, env, stdin="", timeout=120):
  """Run argv in its own session (so the supervisor's signal dance is scoped)."""
  p = subprocess.Popen(
    argv,
    cwd=str(cwd),
    env=env,
    text=True,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    start_new_session=True,
  )
  try:
    out, err = p.communicate(input=stdin, timeout=timeout)
  except subprocess.TimeoutExpired:
    os.killpg(os.getpgid(p.pid), signal.SIGKILL)
    out, err = p.communicate()
  return out, err, p.returncode


@pytest.mark.integration
def test_cmk_interpret_vendored_tool_mode(tmp_path):
  # Control: tool-mode interpret WORKS when compose.mk is vendored in CWD.
  shutil.copy(COMPOSE_MK, tmp_path / "compose.mk")
  (tmp_path / "compose.mk").chmod(0o755)
  (tmp_path / "chain.cmk").write_text(CHAIN)
  out, err, _ = _run(
    ["./compose.mk", "mk.interpret!", "chain.cmk"],
    cwd=tmp_path,
    env=_staged_env(tmp_path),
  )
  assert "one" in out and "two" in out, err


@pytest.mark.integration
def test_cmk_interpret_global_library_mode(cmk, tmp_path, global_bin):
  # Control: LIBRARY mode (global include) interpret WORKS -- CMK_SRC is the
  # absolute include path, so `cat ${CMK_SRC}` succeeds.
  (tmp_path / "chain.cmk").write_text(CHAIN)
  (tmp_path / "Makefile").write_text(
    GUARDED_INCLUDE + "runit:; $(make) mk.interpret! chain.cmk\n"
  )
  out, _, _ = _run(
    ["make", "runit"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
    timeout=120,
  )
  assert "one" in out and "two" in out


@pytest.mark.integration
def test_cmk_interpret_global_tool_mode(tmp_path, global_bin):
  # Fixed gap: global TOOL-mode interpret works now that standalone CMK_SRC
  # resolves to the real abspath (compose.mk:357 -> cmk.self), so mk.interpret's
  # `cat ${CMK_SRC}` (compose.mk:2280) finds compose.mk with no local copy.
  (tmp_path / "chain.cmk").write_text(CHAIN)
  out, err, _ = _run(
    ["compose.mk", "mk.interpret!", "chain.cmk"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
  )
  assert "one" in out and "two" in out, (out, err)


# `${__target__.__doc__}` (target-docstring reflection) reads the running target's `@#`
# via the exported `_cmk_blk_docstring` extractor over ${__interpreting__}/${MAKEFILE_LIST}
# -- both must resolve under global/vendored install so the doc is findable at runtime.
# A `'''`-authored docstring lowers to `@#` in the interpreted makefile (unique target
# name avoids any `__main__` collision in the extractor).
DOC_CHAIN = (
  "doctarget:\n\t'''chain docstring'''\n"
  '\t@echo "doc=[${__target__.__doc__}]"\n'
  "__main__: doctarget\n"
)


@pytest.mark.integration
def test_cmk_targetdoc_vendored_tool_mode(tmp_path):
  shutil.copy(COMPOSE_MK, tmp_path / "compose.mk")
  (tmp_path / "compose.mk").chmod(0o755)
  (tmp_path / "doc.cmk").write_text(DOC_CHAIN)
  out, err, _ = _run(
    ["./compose.mk", "mk.interpret!", "doc.cmk"],
    cwd=tmp_path,
    env=_staged_env(tmp_path),
  )
  assert "doc=[chain docstring]" in out, (out, err)


@pytest.mark.integration
def test_cmk_targetdoc_global_tool_mode(tmp_path, global_bin):
  (tmp_path / "doc.cmk").write_text(DOC_CHAIN)
  out, err, _ = _run(
    ["compose.mk", "mk.interpret!", "doc.cmk"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
  )
  assert "doc=[chain docstring]" in out, (out, err)


@pytest.mark.integration
def test_cmk_targetdoc_global_library_mode(cmk, tmp_path, global_bin):
  (tmp_path / "doc.cmk").write_text(DOC_CHAIN)
  (tmp_path / "Makefile").write_text(
    GUARDED_INCLUDE + "runit:; $(make) mk.interpret! doc.cmk\n"
  )
  out, _, _ = _run(
    ["make", "runit"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
    timeout=120,
  )
  assert "doc=[chain docstring]" in out


@pytest.mark.integration
def test_cmk_compile_shebang_resolves_global(tmp_path, global_bin):
  # Characterization: the compiled shebang's interpreter IS absolute under a
  # global install (so a compiled artifact's `./x.cmk` re-invocation works).
  out, _, _ = _run(
    ["compose.mk", "mk.compile"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
    stdin=CHAIN,
  )
  first = out.splitlines()[0] if out else ""
  assert first.startswith("#!/usr/bin/env -S")
  assert str(global_bin) in first  # interpreter path is absolute


@pytest.mark.integration
def test_cmk_compile_makefilelist_absolute_global(tmp_path, global_bin):
  # Fixed gap: the compiled `MAKEFILE_LIST+=${CMK_SRC}` is now absolute under a
  # global install (CMK_SRC = cmk.self), so a compiled artifact's include
  # reference resolves regardless of CWD.
  out, _, _ = _run(
    ["compose.mk", "mk.compile"],
    cwd=tmp_path,
    env=_staged_env(global_bin),
    stdin=CHAIN,
  )
  ml = [ln for ln in out.splitlines() if ln.startswith("MAKEFILE_LIST+=")]
  assert ml, out
  assert str(global_bin) in ml[0]  # absolute, not bare "compose.mk"


# --- Writable-staging-dir resolution (CMK_STAGE_DIR) --------------------------
# compose.mk writes host-side staged artifacts (.tmp.module.*, native/, the
# remade __hosted__ cache) into CMK_STAGE_DIR = CMK_MODULES_DIR when it exists
# and is writable, else the always-writable CMK_XDG_CACHE. This keeps a
# global/pip install -- whose CMK_MODULES_DIR points at the READ-ONLY bundled
# plugins share -- from hard-failing every staged import / native compile, while
# the writable ./.cmk case still stages under the workspace (container-visible).


def _stage_env(xdg, **extra):
  # Redirect the XDG cache into the test's tmp_path so the fallback is hermetic.
  return {"CMK_XDG_CACHE": str(xdg), **extra}


@pytest.mark.integration
def test_stage_dir_prefers_writable_modules_dir(cmk, tmp_path):
  # Writable modules dir (the vendored ./.cmk case) -> CMK_STAGE_DIR IS it, so
  # staging stays under the cwd/workspace bind-mount and remains container-visible.
  mods = tmp_path / "mods"
  mods.mkdir()
  xdg = tmp_path / "xdg"
  xdg.mkdir()
  r = cmk(
    "mk.get/CMK_STAGE_DIR",
    cwd=tmp_path,
    env=_stage_env(xdg, CMK_MODULES_DIR=str(mods)),
  )
  assert r.ok, r.stderr
  assert str(mods) in r.stdout
  assert str(xdg) not in r.stdout


@pytest.mark.integration
def test_stage_dir_falls_back_when_modules_dir_readonly(cmk, tmp_path):
  # Read-only modules dir (the global/pip bundled-share case) -> CMK_STAGE_DIR
  # diverts to the writable XDG cache instead of hard-failing on the first write.
  ro = tmp_path / "ro"
  ro.mkdir()
  ro.chmod(0o555)
  xdg = tmp_path / "xdg"
  xdg.mkdir()
  try:
    r = cmk(
      "mk.get/CMK_STAGE_DIR",
      cwd=tmp_path,
      env=_stage_env(xdg, CMK_MODULES_DIR=str(ro)),
    )
  finally:
    ro.chmod(0o755)  # let pytest clean the tmp dir up
  assert r.ok, r.stderr
  assert str(xdg) in r.stdout


@pytest.mark.integration
def test_module_import_stages_under_readonly_modules_dir(cmk, tmp_path):
  # End-to-end: a namespaced import.module (the non-fast-path that MUST stage)
  # compiles + runs even when CMK_MODULES_DIR is read-only, by staging into XDG.
  # Before CMK_STAGE_DIR, the unconditional mkdir/write hard-failed at parse.
  (tmp_path / "mod.cmk").write_text("greet:; @echo hello-staged\n")
  (tmp_path / "Makefile").write_text(
    f"include {COMPOSE_MK}\n"
    "$(call import.module, file=mod.cmk namespace=demo prefix=.)\n"
    "top: demo.greet\n"
  )
  ro = tmp_path / "ro"
  ro.mkdir()
  ro.chmod(0o555)
  xdg = tmp_path / "xdg"
  xdg.mkdir()
  try:
    r = cmk(
      "top",
      makefile=tmp_path / "Makefile",
      cwd=tmp_path,
      env=_stage_env(xdg, CMK_MODULES_DIR=str(ro)),
    )
  finally:
    ro.chmod(0o755)
  assert r.ok, r.stderr
  assert "hello-staged" in r.stdout
  assert not list(ro.glob(".tmp.module.*"))  # nothing written into the RO dir
