"""Machine / host / container dispatch hierarchy -- a regression net for the ambient KINDs.

Pins the CURRENT host-vs-container split so the `HOST_AMBIENT`-sentinel retirement (moving the
img-branch into explicit `cmk.host` / `cmk.container` subkinds) is behavior-preserving:

  - a no-img machine dispatches on the HOST         (`.run = host.dispatch/<entrypoint>`,
    `.__call__` -> `cmk.host.exec`)
  - a container dispatches into DOCKER              (`.run = _crun/<name>`,
    `.__call__` -> `docker.run.sh`)
  - `host.local` IS-A machine and IS-A host; a container IS-A container, NOT a host
  - a host machine actually executes on the host, docker-free

All docker-free: declaring a container registers config only (no pull/run), so its `.run`/`.__call__`
are just macro values to inspect.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

_PROBE_SRC = (
  "open cmk\n"
  "machine hostpy(| entrypoint=python3 |)\n"
  "container box(| img=alpine entrypoint=sh |)\n"
  "$(info MHOSTRUN=[$(hostpy.run)])\n"
  "$(info MBOXRUN=[$(box.run)])\n"
  "$(info MHOSTCALL=[$(hostpy.__call__)])\n"
  "$(info MBOXCALL=[$(box.__call__)])\n"
  "$(info MHLMACH=[$(call isinstance,host.local,cmk.machine)])\n"
  "$(info MHLHOST=[$(call isinstance,host.local,cmk.host)])\n"
  "$(info MBOXCON=[$(call isinstance,box,cmk.container)])\n"
  "$(info MBOXHOST=[$(call isinstance,box,cmk.host)])\n"
  "$(info MHNHOST=[$(call isinstance,host.native.bash,cmk.host)])\n"
  "$(info MHNRESOLVE=[$(call _cmk.host.machine,host.native.bash)])\n"
  "$(info MHNBARE=[$(call _cmk.host.machine,bash)])\n"
  "$(info MBOX_AMBIENT=[$(call isinstance,box,Ambient)])\n"
  "$(info MBOX_RUNNABLE=[$(call Runnable.provided_by,box)])\n"
  "__main__:; @true\n"
)


def _run(src, *targets, timeout=120):
  f = REPO / ".tmp.machine.hierarchy.cmk"
  f.write_text(src)
  try:
    r = subprocess.run(
      [str(COMPOSE), "cmk", "run", str(f), *targets],
      cwd=str(REPO),
      stdin=subprocess.DEVNULL,
      capture_output=True,
      text=True,
      errors="replace",
      timeout=timeout,
    )
    return r.returncode, r.stdout + r.stderr
  finally:
    f.unlink(missing_ok=True)


@pytest.fixture(scope="module")
def probe():
  rc, out = _run(_PROBE_SRC)
  assert rc == 0, out
  return out


def test_host_machine_run_is_host_dispatch(probe):
  # a no-img machine runs on the host: `.run` = `host.dispatch/<entrypoint>`, never `_crun`.
  assert "MHOSTRUN=[host.dispatch/python3]" in probe


def test_container_run_is_docker_dispatch(probe):
  # a container runs in docker: `.run` = `_crun/<name>`.
  assert "MBOXRUN=[_crun/box]" in probe


def test_host_call_routes_to_host_exec(probe):
  # a host machine's `.__call__` prepends the entrypoint and runs via `cmk.host.exec`, NOT docker.
  # The cmd tail carries the interpreter-argv splice (CMK_LAMBDA_ARGV), same as the container arm.
  line = next(l for l in probe.splitlines() if l.startswith("MHOSTCALL="))
  assert "cmk.host.exec" in line
  assert 'cmd="python3 ' in line
  assert "CMK_LAMBDA_ARGV" in line
  assert "docker.run.sh" not in line


def test_container_call_routes_to_docker(probe):
  # a container's `.__call__` carries img/entrypoint and runs via `docker.run.sh`, NOT the host.
  line = next(l for l in probe.splitlines() if l.startswith("MBOXCALL="))
  assert "docker.run.sh" in line
  assert "img=alpine" in line
  assert "cmk.host.exec" not in line


def test_host_local_is_machine_and_host(probe):
  assert "MHLMACH=[1]" in probe
  assert "MHLHOST=[1]" in probe


def test_container_is_container_not_host(probe):
  # a container is-a container but is NOT a host (the two subkinds are disjoint).
  assert "MBOXCON=[1]" in probe
  assert "MBOXHOST=[]" in probe


def test_host_native_interpreters_are_hosts(probe):
  # the built-in interpreters live under `host.native.*` as `cmk.host` singletons, named in full
  # (`in host.native.bash`), which `_cmk.host.machine` dispatches as-is.  There is NO bare `in bash`
  # alias any more -- a bare name resolves to itself (an ordinary, undefined ambient).
  assert "MHNHOST=[1]" in probe
  assert "MHNRESOLVE=[host.native.bash]" in probe
  assert "MHNBARE=[bash]" in probe


def test_machine_is_ambient_and_runnable(probe):
  # a machine conforms to the `Ambient` protocol (MEMBERSHIP -- `.__ambient_parent__` + registration; was
  # the `cmk.ambient` class, now mixed via `bases=Ambient`) AND the `Runnable` capability (it has `.run`).
  assert "MBOX_AMBIENT=[1]" in probe
  assert "MBOX_RUNNABLE=[1]" in probe


def test_code_object_runnable_only_when_bound():
  # a code-object is content + an optional machine BINDING (has-a, not is-a): UNBOUND it has no
  # `.__machine__` and does NOT conform to `Runnable`; BOUND it carries `.__machine__` and DOES.
  src = (
    "open cmk\n"
    "code cobj_unbound(|\n  x\n|)\n"
    "myint/%:; @cat ${*}\n"
    "code cobj_bound(entrypoint=@myint)(|\n  y\n|)\n"
    "$(info MU_RUN=[$(call Runnable.provided_by,cobj_unbound)])\n"
    "$(info MU_MACHINE=[$(origin cobj_unbound.__machine__)])\n"
    "$(info MB_RUN=[$(call Runnable.provided_by,cobj_bound)])\n"
    "$(info MB_MACHINE=[$(origin cobj_bound.__machine__)])\n"
    "__main__:; @true\n"
  )
  rc, out = _run(src)
  assert rc == 0, out
  assert "MU_RUN=[]" in out
  assert "MU_MACHINE=[undefined]" in out
  assert "MB_RUN=[1]" in out
  assert "MB_MACHINE=[file]" in out


def test_host_machine_executes_docker_free():
  # behavioral: a block run `in host.local` executes on the host shell (no docker).
  rc, out = _run(
    "open cmk\nd:\n  (| echo HOSTEXEC_MARK_42 |) in host.local\n", "d"
  )
  assert rc == 0, out
  assert "HOSTEXEC_MARK_42" in out


def test_ambient_parent_propagates_into_block():
  # `X/%` dispatch exports `__ambient_parent__=<X's parent>` into the block's env, so the block
  # knows what encloses it -- a machine's default parent is `host.local`.
  rc, out = _run(
    'open cmk\nmachine hm(| entrypoint=bash |)\n'
    'd:\n  (| echo "AP=[$__ambient_parent__]" |) in hm\n', "d"
  )
  assert rc == 0, out
  assert "AP=[host.local]" in out


def test_out_from_top_recipe_runs_on_host():
  # `out` navigates to the dynamic `__ambient_parent__`.  A top-level recipe's parent is UNSET, so it
  # defaults to `host.local` -- `out` there = escape to the host, and the block RUNS (existing
  # behavior preserved).  `OutwardsUndefined` is reserved for going BEYOND host.local (its parent is
  # explicitly empty), which cannot happen from a top-level recipe.
  rc, out = _run("open cmk\nd:\n  (| echo OUT_RAN_ON_HOST |) out\n", "d")
  assert rc == 0, out
  assert "OUT_RAN_ON_HOST" in out
