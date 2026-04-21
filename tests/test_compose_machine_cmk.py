"""compose.service / compose.group / compose.machine -- the compose analog of Dockerfile.

Dockerfile/container (tests/test_machine_hierarchy_cmk.py, test_dockerfile_build_cmk.py,
test_dsl_machine_cmk.py) is the REFERENCE machine: a compose-backed machine must present the
same interface -- is-a cmk.machine, a `.run`/`.__call__`/`.__in__` that route to its OWN runtime
(compose, not the host), and machine= dsl-backing.  Any deviation from that reference is a bug in
the compose kinds, not in the test.

The kinds live in .cmk/graal.cmk (the spike); a trivial `alpine` service exercises them without
the heavy graal image build.  Interface probes are docker-free (COMPOSE_MISSING=1 skips the
parse-time compose service scan); the run round-trip is needs_docker.
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("graal-interop.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# A trivial single-service compose.service (`box`), a dsl backed by it, and an instance -- plus
# the machine-interface fields to inspect.  Mirrors the `_PROBE_SRC` shape in
# test_machine_hierarchy_cmk.py (declare, then `$(info ...)` the interface).
_PROBE = (
    "from cmk import dsl\n"
    "compose.service box(|\n"
    "image: alpine\n"
    "entrypoint: sh\n"
    "|)\n"
    "dsl calc(machine=box)(| |)\n"
    "calc sq(| echo hi |)\n"
    "$(info CSMACHINE=[$(call isinstance,box,cmk.machine)])\n"
    "$(info CSCONTAINER=[$(call isinstance,box,cmk.container)])\n"
    "$(info CSCLASS=[$(box.__class__)])\n"
    "$(info CSIN=[$(if $(filter-out undefined,$(origin box.__in__)),y,n)])\n"
    "$(info CSRUN=[$(box.run)])\n"
    "$(info CSCALL=[$(box.__call__)])\n"
    "$(info CSDSLMACH=[$(calc.__machine__)])\n"
    "$(info CSINSTMACH=[$(sq.__machine__)])\n"
    "$(info CSCONTENT=[$(subst $(nl),<NL>,$(box.content))])\n"
    "__main__:; @true\n"
)


def _run(src, *targets, docker=False, timeout=180):
    f = REPO / ".tmp.compose.machine.cmk"
    f.write_text("#!/usr/bin/env -S ./compose.mk cmk run\n" + src)
    env = dict(os.environ)
    if not docker:
        env["COMPOSE_MISSING"] = "1"
    try:
        r = subprocess.run(
            [str(COMPOSE), "cmk", "run", str(f), *targets],
            cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
            text=True, errors="replace", timeout=timeout, env=env,
        )
        return r.returncode, r.stdout + r.stderr
    finally:
        f.unlink(missing_ok=True)


@pytest.fixture(scope="module")
def probe():
    rc, out = _run(_PROBE)
    assert rc == 0, out
    return out


# -- is-a machine (the reference: a container is-a cmk.machine) --

def test_composeservice_is_a_machine(probe):
    # like a Dockerfile/container, a compose.service instance is-a cmk.machine.
    assert "CSMACHINE=[1]" in probe


def test_composeservice_class(probe):
    assert "CSCLASS=[compose.service]" in probe


# -- the machine dispatch hooks route to the compose runtime, NOT the host --
# (reference: a no-img machine routes to the host; a container pins .run/.__call__ to docker.
#  a compose machine must pin them to compose -- if it falls through to host.dispatch/host.exec
#  that is the deviation to fix.)

def test_composeservice_has_in_hook(probe):
    assert "CSIN=[y]" in probe


def test_composeservice_run_routes_to_compose_not_host(probe):
    # reference: container `.run = _crun/<self>`.  compose: `.run = <stem>/<svc>` (the service
    # dispatch), NEVER `host.dispatch/<entrypoint>`.
    line = next(l for l in probe.splitlines() if l.startswith("CSRUN="))
    assert "host.dispatch" not in line, line
    assert ".tmp.box/box" in line, line


def test_composeservice_call_routes_to_compose_not_host(probe):
    # reference: container `.__call__` runs via `docker.run.sh`.  compose: routes to the service
    # dispatch, NEVER `cmk.host.exec`.
    line = next(l for l in probe.splitlines() if l.startswith("CSCALL="))
    assert "cmk.host.exec" not in line, line
    assert ".tmp.box/box" in line, line


def test_composeservice_build_is_cleanly_defined(probe):
    # a compose machine has a `.build` like a container -- and it must be defined ONCE (no
    # `overriding recipe`).  The diamond compose.service(compose.group,compose.machine) re-stamped it
    # twice until `.build` was made a prerequisite (which make merges) rather than a 2nd recipe.
    assert "overriding recipe" not in probe, probe
    assert "ignoring old recipe" not in probe, probe


# -- machine= dsl-backing (mirrors test_dsl_machine_cmk.test_bind_existing_machine) --

def test_dsl_records_the_composeservice_machine(probe):
    assert "CSDSLMACH=[box]" in probe
    assert "CSINSTMACH=[box]" in probe


# -- the raw body wraps into a one-service compose file (the ergonomic form) --

def test_composeservice_wraps_body_into_one_service(probe):
    line = next(l for l in probe.splitlines() if l.startswith("CSCONTENT="))
    assert "services:<NL>  box:<NL>" in line, line  # services: / <self>: preamble auto-added
    assert "image: alpine" in line, line


# -- needs_docker: the round-trip (a body runs in the service and prints) --

@pytest.mark.needs_docker
def test_composeservice_runs_a_body(tmp_path):
    src = (
            "from cmk import dsl\n"
    "compose.service box(|\n"
        "image: alpine\n"
        "entrypoint: sh\n"
        "|)\n"
        "dsl sh_in(machine=box)(| |)\n"
        # /etc/alpine-release exists ONLY in the alpine container, so this proves the body ran
        # inside the compose service (not on the host).
        "sh_in hello(| head -1 /etc/alpine-release && echo COMPOSE-RAN-OK |)\n"
        "__main__:\n\thello()\n"
    )
    rc, out = _run(src, docker=True, timeout=400)
    assert rc == 0, out
    assert "COMPOSE-RAN-OK" in out, out
