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
HOST_NAME = subprocess.run(["hostname"], capture_output=True, text=True, timeout=30).stdout.strip()

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


# Re-invoking the written file is what makes each hop a separate process, so the chain is real.
_CHAIN_SRC = (
  "open cmk\n"
  "machine outer(entrypoint=bash)(| |)\n"
  "machine inner(entrypoint=bash)(| |)\n"
  "lone:\n"
  '  (| echo "L1_AP=[$__ambient_parent__] L1_CUR=[$__ambient__]" |) in outer\n'
  "nest:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk deep |) in outer\n"
  "deep:\n"
  '  (| echo "L2_AP=[$__ambient_parent__] L2_CUR=[$__ambient__]" |) in inner\n'
  "hop:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk mid |) in outer\n"
  "mid:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk leaf |) in inner\n"
  "leaf:\n"
  '  (| echo "OUT_AP=[$__ambient_parent__] OUT_CUR=[$__ambient__]" |) out\n'
  "esc:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk root |) in outer\n"
  "root:\n"
  '  (| echo "ROOT_CUR=[$__ambient__] ROOT_AP=[$__ambient_parent__] ROOT_ST=[$__ambient_stack__]" |) out\n'
  "forge:\n"
  "  (| __ambient_parent__=inner ./compose.mk cmk run .tmp.machine.hierarchy.cmk forged |) in outer\n"
  "forged:\n"
  '  (| echo "FORGE_LANDED" |) out\n'
  "named:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk named.ok |) in outer\n"
  "named.ok:\n"
  '  (| echo "NAMED_CUR=[$__ambient__]" |) out outer\n'
  "misnamed:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk misnamed.bad |) in outer\n"
  "misnamed.bad:\n"
  '  (| echo "MISNAMED_LANDED" |) out inner\n'
)

# Namespaces nested two deep: registered, parenting their members, and `in`-dispatchable.
_NS_SRC = (
  "open cmk\n"
  "namespace zone(|\n"
  "  namespace grp(|\n"
  "    machine kid(entrypoint=bash)(| |)\n"
  "  |)\n"
  "|)\n"
  "reg:\n"
  '  printf "NSREG=[$(call __ambients__.has,zone)$(call __ambients__.has,zone.grp)]'
  ' GRPAP=[$(zone.grp.__ambient_parent__)] KIDAP=[$(zone.grp.kid.__ambient_parent__)]\\n"\n'
  "enter:\n"
  '  (| echo "NS_CUR=[$__ambient__] NS_AP=[$__ambient_parent__]" |) in zone.grp\n'
  "step:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk step.mid |) in zone.grp.kid\n"
  "step.mid:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk step.top |) out\n"
  "step.top:\n"
  '  (| echo "STEP_CUR=[$__ambient__] STEP_AP=[$__ambient_parent__]" |) out\n'
)


def test_nested_in_composes_the_chain():
  """A block sent into `inner` from inside `outer` sees `outer` as its parent.

  Before the chain was dynamic, every machine reported the static `host.local`.
  """
  rc, out = _run(_CHAIN_SRC, "lone", "nest", timeout=300)
  assert rc == 0, out[-2000:]
  assert "L1_AP=[host.local] L1_CUR=[outer]" in out, out[-2000:]
  assert "L2_AP=[outer] L2_CUR=[inner]" in out, out[-2000:]


def test_multihop_out_lands_on_the_parents_own_parent():
  """`out` from two levels deep lands in `outer` carrying outer's own parent.

  Landing with `OUT_AP=[outer]` would mean the destination became its own parent, which is the
  bug the non-pushing reenter door exists to prevent: the next `out` would bounce straight back.
  """
  rc, out = _run(_CHAIN_SRC, "hop", timeout=300)
  assert rc == 0, out[-2000:]
  assert "OUT_CUR=[outer]" in out, out[-2000:]
  assert "OUT_AP=[host.local]" in out, out[-2000:]
  assert "OUT_AP=[outer]" not in out, out[-2000:]


def test_out_to_the_host_relabels_the_chain():
  """`out` from a machine whose parent is the host lands relabelled at the root.

  Reporting `ROOT_CUR=[outer]` would mean the block claims to be in the machine it just left.
  The empty parent is the root sentinel a further `out` faults on.
  """
  rc, out = _run(_CHAIN_SRC, "esc", timeout=300)
  assert rc == 0, out[-2000:]
  assert "ROOT_CUR=[host.local] ROOT_AP=[] ROOT_ST=[]" in out, out[-2000:]


def test_a_rewritten_parent_link_faults_instead_of_moving():
  """The parent link and the stack top are the same value, so a rewritten one is caught.

  Entry pushes exactly what it assigns as the parent, so the two can only disagree when
  something edits the env out of band.  Moving anyway lands a block whose labels contradict
  where it went.
  """
  rc, out = _run(_CHAIN_SRC, "forge", timeout=300)
  assert rc != 0, out[-2000:]
  assert "AmbientChainMismatch" in out, out[-2000:]
  assert "FORGE_LANDED" not in out, out[-2000:]


def test_out_by_name_accepts_the_ambient_being_left():
  """`out <name>` names the ambient being left, matching the calculus arity for `out m`."""
  rc, out = _run(_CHAIN_SRC, "named", timeout=300)
  assert rc == 0, out[-2000:]
  assert "NAMED_CUR=[host.local]" in out, out[-2000:]


def test_out_by_name_rejects_a_different_ambient():
  """Naming an ambient you are not in faults by name, rather than moving somewhere else."""
  rc, out = _run(_CHAIN_SRC, "misnamed", timeout=300)
  assert rc != 0, out[-2000:]
  assert "OutwardsUnexpected" in out, out[-2000:]
  assert "MISNAMED_LANDED" not in out, out[-2000:]


# The outward move as a protocol method: each kind says how a block leaves it, or refuses.
_OUT_SRC = (
  "open cmk\n"
  "machine outer(entrypoint=bash)(| |)\n"
  "machine plain(entrypoint=bash)(| |)\n"
  "class Loud(bases=cmk.machine)(|\n"
  "  self.__out__ = $(info OUTHOOK=[${self}])$(call ambient.out.default,${__args__})\n"
  "|)\n"
  "Loud noisy(entrypoint=bash)(| |)\n"
  "class Sealed(bases=cmk.machine)(|\n"
  "  self.__out__ = $(call ambient.out.unavailable,${self})\n"
  "|)\n"
  "Sealed vault(entrypoint=bash)(| |)\n"
  "hook:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk hook.leaf |) in noisy\n"
  "hook.leaf:\n"
  '  (| echo "HOOK_CUR=[$__ambient__]" |) out\n'
  "sealed:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk sealed.leaf |) in vault\n"
  "sealed.leaf:\n"
  '  (| echo "SEALED_LANDED" |) out\n'
  "default:\n"
  "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk default.leaf |) in plain\n"
  "default.leaf:\n"
  '  (| echo "PLAIN_CUR=[$__ambient__]" |) out\n'
)


def test_a_kind_can_override_how_a_block_leaves_it():
  """`__out__` is the dual of `__in__`: the ambient being left says how the block leaves.

  Without the hook the exit logic can only live in one conditional switching over kinds,
  which is how a dead arm survived unnoticed.
  """
  rc, out = _run(_OUT_SRC, "hook", timeout=300)
  assert rc == 0, out[-2000:]
  assert "OUTHOOK=[noisy]" in out, out[-2000:]
  assert "HOOK_CUR=[host.local]" in out, out[-2000:]


def test_a_kind_with_no_way_back_refuses_the_move():
  """An ambient that cannot offer a way back faults by name instead of doing something adjacent.

  This is the shape a vm guest needs: no agent, no exit, and the block must not land
  somewhere else quietly.
  """
  rc, out = _run(_OUT_SRC, "sealed", timeout=300)
  assert rc != 0, out[-2000:]
  assert "OutwardsUnavailable: vault" in out, out[-2000:]
  assert "SEALED_LANDED" not in out, out[-2000:]


def test_a_kind_without_an_override_still_leaves_by_the_default():
  """Adding the hook must not change what an ordinary machine does."""
  rc, out = _run(_OUT_SRC, "default", timeout=300)
  assert rc == 0, out[-2000:]
  assert "PLAIN_CUR=[host.local]" in out, out[-2000:]


def test_an_outward_move_between_host_machines_stays_in_place():
  """Host machines share one context, so leaving one for another relocates nothing.

  Checked against the host's own name, read before the run.  The contrast with the
  container case is why the exit belongs to the kind: the same operator has to mean
  different work depending on what is being left.
  """
  src = (
    "open cmk\n"
    "machine outer(entrypoint=bash)(| |)\n"
    "machine inner(entrypoint=bash)(| |)\n"
    "hop:\n"
    "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk mid |) in outer\n"
    "mid:\n"
    "  (| ./compose.mk cmk run .tmp.machine.hierarchy.cmk leaf |) in inner\n"
    "leaf:\n"
    '  (| echo "HOST_AT=[`hostname`]" |) out\n'
  )
  rc, out = _run(src, "hop", timeout=300)
  assert rc == 0, out[-2000:]
  assert f"HOST_AT=[{HOST_NAME}]" in out, out[-2000:]


def test_namespace_is_an_ambient_with_a_door():
  """A namespace registers, parents its members, and accepts an `in` dispatch.

  Before, it conformed to the protocol structurally while carrying none of the runtime half:
  `in <ns>` had no rule to make, and a member's parent link still pointed at the host.
  Nesting composes, so the inner group's parent is the outer group, not the host.
  """
  rc, out = _run(_NS_SRC, "reg", "enter", timeout=300)
  assert rc == 0, out[-2000:]
  assert "NSREG=[zonezone.grp] GRPAP=[zone] KIDAP=[zone.grp]" in out, out[-2000:]
  assert "NS_CUR=[zone.grp] NS_AP=[zone]" in out, out[-2000:]


def test_outward_climb_walks_the_nested_groups_one_level_at_a_time():
  """Two outward moves from a member reach the outer group, through the inner one.

  Entering a member pushes one frame, so the climb outruns the stack: each pop refills it
  from the destination's declared parent, which is what keeps the second move legal.
  """
  rc, out = _run(_NS_SRC, "step", timeout=300)
  assert rc == 0, out[-2000:]
  assert "STEP_CUR=[zone] STEP_AP=[host.local]" in out, out[-2000:]
  assert "AmbientChainMismatch" not in out, out[-2000:]
