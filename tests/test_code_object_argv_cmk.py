"""Code-object argv passing -- a minted code-object called with CLI args reaches the interpreter.

This is practical payoff #1 of TODO-dsl-fragment.md (scripts-as-callable-values-with-args): a code
object invoked as a callform `prog(--foo x --bar)` must thread those args to the bound interpreter,
so an embedded optparse/argparse script sees them in `sys.argv`.  Two halves, pinned here:

  * OBJECT half (docker-free): the code-object carries a `.__call__` that folds `${__args__}` into
    `CMK_LAMBDA_ARGV`.  Without it the smart-send falls to `$(call prog,args)`, whose body has no
    `$1`, so args vanish (the old TODO-code-object-argv failure).
  * SEAM half (host arm docker-free via `entrypoint=sh`, container arm docker-gated): the run seam
    (`cmk.machine.__call__`, compose.mk ~4249) splices `CMK_LAMBDA_ARGV` into the command, the same
    way `host.dispatch` (~4414) already does.

Kept green alongside test_code_object_parity_cmk.py (the construction contract) and
test_code_object_template_cmk.py (the Templatable surface).
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(src, tmp_path, goal="probe", cwd=None):
  f = tmp_path / "argv.cmk"
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
    timeout=120,
  )
  return r.stdout + r.stderr


# Module-level probes (parse-time, so recipe shell-quoting can't eat the expansion).  `_c` captures
# the `.__call__` expansion once at module scope.
CALL_PROBE = r"""
from cmk import container
container py(| img=python:3.11-slim entrypoint=python |)
py.polyglot prog(| import sys; print(sys.argv[1:]) |)

# Guard the eager probe on origin: parse re-runs across passes (incl. an internal one where the
# else-branch members are not yet minted), and the real smart-send guards the same way before it
# dispatches `.__call__`, so an unguarded call would only warn in a pass real usage never hits.
_c := $(if $(filter file override,$(origin prog.__call__)),$(call prog.__call__,--foo x --bar))
$(info CO_CALL_HAS_ARGV=[$(if $(findstring CMK_LAMBDA_ARGV,$(_c)),yes,no)])
$(info CO_CALL_HAS_ARGS=[$(if $(findstring --foo x --bar,$(_c)),yes,no)])

probe:; @true
"""


def test_code_object_has_call_that_threads_argv(tmp_path):
  # OBJECT half: a code-object must carry `.__call__`, and calling it with a space-form arg string
  # must fold that string into a CMK_LAMBDA_ARGV env-prefix (not drop it).
  out = _run(CALL_PROBE, tmp_path)
  assert "CO_CALL_HAS_ARGV=[yes]" in out, out          # threads via CMK_LAMBDA_ARGV
  assert "CO_CALL_HAS_ARGS=[yes]" in out, out          # the arg string survives verbatim


# End-to-end host arm (docker-free): bind to `sh` on the host; the body echoes its positional args,
# so a passing run proves argv crossed the whole file-seam to the interpreter's command line.
HOST_E2E = r"""
from cmk import host
code prog(entrypoint=sh)(|
  echo "ARGV=[$@]"
|)
probe:; prog(--foo x --bar)
"""


def test_code_object_argv_reaches_host_interpreter(tmp_path):
  # SEAM half (host arm): the spliced CMK_LAMBDA_ARGV reaches `sh <file> <args>`.
  out = _run(HOST_E2E, tmp_path, cwd=tmp_path)
  assert "ARGV=[--foo x --bar]" in out, out


# End-to-end container arm (docker-gated): the interpreter-3.cmk shape as a container.polyglot.
CONTAINER_E2E = r"""
from cmk import container
export python_img ?= python:3.11-slim-bookworm
container py(| img=$(python_img) entrypoint=python |)
py.polyglot prog(|
  import sys
  print("ARGV=%s" % sys.argv[1:])
|)
probe:; prog(alpha beta)
"""


@pytest.mark.docker
@pytest.mark.needs_docker
def test_code_object_argv_reaches_container_interpreter(tmp_path):
  # SEAM half (container arm): argv must be baked into the docker command before crossing the
  # boundary (the container never sees the host env var).
  out = _run(CONTAINER_E2E, tmp_path, cwd=tmp_path)
  assert "ARGV=['alpha', 'beta']" in out, out
