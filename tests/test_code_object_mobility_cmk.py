"""Code-object ambient mobility -- run one code-object's body in a chosen ambient (`&<obj> in <X>`).

This is practical payoff #2 of TODO-dsl-fragment.md (run-anywhere-without-a-rewrite): the same authored
body runs on the host or in a container, selected at the call site, via the canonical cmk-lang sugar
`&<obj> in <ambient>` (a standalone recipe line).  The leading `&` marks it cmk-lang, so a bare `x in y`
stays an ordinary shell statement.  It routes the named receiver through the ambient's in-dispatch.

This works for code-objects with NO compiler change: the `&<recv> in <machine>` form already existed for
named receivers (handles/captured fragments), and Phase 0 (TODO-dsl-fragment.md) proved the historical
fork-bomb is gone -- the run-seam materializer prefers the source def (`.__ctor_src__`) over the shadowed
run-alias, so feeding a code-object back through the dispatcher reads the body, not the alias.

Host arm is docker-free (bind to host.local); container arm is docker-gated.
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(src, tmp_path, goal, cwd=None):
  f = tmp_path / "mob.cmk"
  f.write_text(src)
  run_cwd = str(cwd or REPO)
  # pin the docker workspace mount to this run's cwd, as conftest's cmk_runner does
  env = {**os.environ, "DOCKER_HOST_WORKSPACE": run_cwd}
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=run_cwd,
    env=env,
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=300,
  )
  return r.stdout + r.stderr


# `&<obj> in <ambient>` must be a standalone recipe line (the form anchors to line-start after the
# indent), so the recipe bodies use a real leading tab.
HOST_E2E = (
  "from cmk import host\n"
  "code prog(bind=host.local)(|\n"
  '  echo "MOBILE ran"\n'
  "|)\n"
  "go:\n"
  "\t&prog in host.local\n"
)


def test_in_sugar_runs_on_host(tmp_path):
  # Host ambient (docker-free): the sugar dispatches the code-object into host.local and runs the body.
  out = _run(HOST_E2E, tmp_path, goal="go", cwd=tmp_path)
  assert "MOBILE ran" in out, out


CONTAINER_E2E = (
  "from cmk import container, host\n"
  "container shbox(| img=debian:bookworm-slim entrypoint=sh |)\n"
  "code prog(bind=host.local)(|\n"
  '  echo "MOBILE ran"\n'
  "|)\n"
  "there:\n"
  "\t&prog in shbox\n"
)


@pytest.mark.docker
@pytest.mark.needs_docker
def test_in_sugar_runs_in_container(tmp_path):
  # Container ambient: the SAME body runs in-container -- the write-once-run-anywhere proof.
  out = _run(CONTAINER_E2E, tmp_path, goal="there", cwd=tmp_path)
  assert "MOBILE ran" in out, out
