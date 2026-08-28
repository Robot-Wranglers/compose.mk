"""Smoke sweep for the committed CMK-language demos.

A thin guard that every committed top-level demo still runs -- or, for the heavy
and interactive ones, still transpiles. Demos are not a substitute for tests:
anything needing real behavioral coverage carries its own dedicated test tagged
via the covers-demo marker, and this sweep only handles what no such test claims.
Scope is git-tracked top-level demos only, so uncommitted work-in-progress and the
demos in the tui subfolder (driven by their own tests) are out.
"""

import re
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
CMK_DEMOS = REPO / "demos" / "cmk"
TESTS_DIR = REPO / "tests"


def _tracked_top_level_demos():
  out = subprocess.run(
    ["git", "ls-files", "demos/cmk/*.cmk"],
    cwd=str(REPO), capture_output=True, text=True,
  ).stdout
  return sorted(
    Path(p).name for p in out.split() if re.fullmatch(r"demos/cmk/[^/]+\.cmk", p)
  )


ALL_DEMOS = _tracked_top_level_demos()

_COVERS_CALL = re.compile(r"covers_demo\(([^)]*)\)")
_CMK_LIT = re.compile(r"""["']([^"']+\.cmk)["']""")


def _covered_demos():
  # demos a dedicated test already claims, so the sweep leaves them alone
  covered = set()
  for pyf in TESTS_DIR.glob("test_*.py"):
    if pyf.name == Path(__file__).name:
      continue
    text = pyf.read_text(encoding="utf-8", errors="replace")
    for call in _COVERS_CALL.finditer(text):
      covered.update(_CMK_LIT.findall(call.group(1)))
  return covered


COVERED = _covered_demos()

# demos that cannot run on a gate (llm, notebook, gui, external runtime): compile-checked
HEAVY = {
  "ollama.cmk", "rag.cmk", "notebooking.cmk", "lean.cmk",
  "julia.cmk", "uv.cmk", "structured-io-nushell.cmk",
  "xpra.cmk", "xpra-net.cmk", "xpra-doom.cmk", "xephyr.cmk",
}

def _is_interactive(name):
  # a demo driving the tux repl needs a tty and cannot be run headless
  return "tux.repl" in (CMK_DEMOS / name).read_text(errors="replace")


# the beam platform is in-flight and not certified: run under the experimental suite instead
EXPERIMENTAL = {d for d in ALL_DEMOS if d.startswith("beam")}

INTERACTIVE = {d for d in ALL_DEMOS if d not in COVERED and _is_interactive(d)}
COMPILE_ONLY = sorted((HEAVY | INTERACTIVE) - COVERED - EXPERIMENTAL)
RUN = [
  d
  for d in ALL_DEMOS
  if d not in COVERED and d not in HEAVY and d not in INTERACTIVE and d not in EXPERIMENTAL
]
EXPERIMENTAL_RUN = sorted(EXPERIMENTAL - COVERED)


def _run_demo(runner, demo):
  r = runner(
    "cmk", "run", f"demos/cmk/{demo}",
    cwd=REPO, timeout=300, env={"CMK_SUPERVISOR": "1"},
  )
  assert r.returncode == 0, (
    f"`cmk run demos/cmk/{demo}` failed (rc={r.returncode})\n{r.stderr[-2000:]}"
  )


@pytest.mark.integration
@pytest.mark.needs_docker
@pytest.mark.parametrize("demo", RUN)
def test_committed_cmk_demo_runs(demo, docker_cmk):
  # every committed demo no dedicated test claims must run clean end to end
  _run_demo(docker_cmk, demo)


@pytest.mark.experimental
@pytest.mark.needs_docker
@pytest.mark.parametrize("demo", EXPERIMENTAL_RUN or ["<none>"])
def test_experimental_cmk_demo_runs(demo, docker_cmk):
  # in-flight demos, carried by no gating suite so a failure never reddens a PR
  if demo == "<none>":
    pytest.skip("no experimental demos")
  _run_demo(docker_cmk, demo)


@pytest.mark.compiler
@pytest.mark.parametrize("demo", COMPILE_ONLY or ["<none>"])
def test_heavy_or_interactive_cmk_demo_compiles(demo, cmk):
  # heavy and interactive demos are not run on the gate but must still transpile
  if demo == "<none>":
    pytest.skip("no heavy or interactive demos")
  r = cmk(
    "cmk", "compile", f"demos/cmk/{demo}",
    cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"},
  )
  assert r.ok, f"`cmk compile demos/cmk/{demo}` failed\n{r.stderr[-1500:]}"


@pytest.mark.unit
def test_heavy_list_names_tracked_demos():
  # the one remaining list stays honest: every heavy name is a real tracked demo
  missing = HEAVY - set(ALL_DEMOS)
  assert not missing, f"heavy names non-existent or untracked demos: {sorted(missing)}"
