"""The class-build model: `Dockerfile(| CONFIG |).container(| code |)`.

`Dockerfile` is a built image (its `.__call__` is build).  The fluent `.` fold
folds a `Dockerfile` operand with a `container` operand through
`Dockerfile.__dot__`: the dunder stamps the container operand's `.__call__` to
(build the image) then (run the operand body as a shell script on it via
`docker.run.def`), and returns the operand so the chain result runs inline.

Compile-level lowering is a docker-free `unit`; the build+run round-trip is
`needs_docker`.  Companion to the demo `demos/cmk/dockerfile-build.cmk`.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("dockerfile-build.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "dockerfile-build.cmk"

FOLD = (
  "from cmk import Dockerfile, container\n"
  "__main__:\n"
  "  Dockerfile(| FROM alpine:3.21 |).container(| echo hi |)\n"
)


def _transpile(src, timeout=120):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r.stdout


def _run(*targets, timeout=300):
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def test_fold_lowers_through_dot_op():
  # both operands construct as throwaway instances, then fold left through
  # `lang.grammar.dot.op` (which dispatches `.__dot__`), and the result runs via dot.run.
  low = _transpile(FOLD)
  assert "$(call lang.grammar.dot.new,Dockerfile," in low, low
  assert "$(call lang.grammar.dot.new,container," in low, low
  assert "$(call lang.grammar.dot.op,$(__fold_" in low, low
  assert "$(call lang.grammar.dot.run,$(__fold_" in low, low


def test_container_defines_the_dot_dunder():
  # the fold is only valid because the kind implements `.__dot__` (a kind without it errors at
  # expand, see test_compiler_cmk.py).  Post container+Dockerfile MERGE it lives on `cmk.container`
  # (a container with a recipe body builds), and `Dockerfile` inherits it as a thin alias.  Assert
  # the method is stamped in the container body and wires build+run, and Dockerfile just subclasses.
  src = COMPOSE.read_text()
  i = src.index("cmk.class cmk.container(")
  body = src[i : i + 2000]
  assert "${self}.__dot__" in body, body[:800]
  assert ".build" in body and "docker.run.def" in body, body[:800]
  j = src.index("cmk.class cmk.Dockerfile")
  assert "bases=cmk.container" in src[j : j + 120], src[j : j + 400]  # thin alias, inherits __dot__


CONTAINER_FOLD = (
  "from cmk import container\n"
  "__main__:\n"
  "  container(| FROM alpine:3.21 |).container(| echo hi |)\n"
)


def test_container_recipe_body_folds_like_dockerfile():
  # NEW FORM: a `container(| FROM .. |)` with a recipe body is a built image too (the merge), so it
  # folds with a run operand identically to the `Dockerfile(| .. |)` form -- both build operands
  # lower through the same `.__dot__` on cmk.container.
  low = _transpile(CONTAINER_FOLD)
  assert "$(call lang.grammar.dot.new,container," in low, low
  assert "$(call lang.grammar.dot.op,$(__fold_" in low, low
  assert "$(call lang.grammar.dot.run,$(__fold_" in low, low


@pytest.mark.needs_docker
def test_fold_builds_then_runs_in_the_image():
  # the round-trip: build alpine, run the operand body as a shell script on it.
  r, out = _run()
  assert r.returncode == 0, out
  assert "hi from the built image" in out, out
  assert "Linux" in out, out


@pytest.mark.needs_docker
def test_container_recipe_body_builds_then_runs():
  # NEW FORM end-to-end: a named `container NAME(kwargs)(| FROM .. |)` with a recipe body builds
  # (img=compose.mk:NAME, src=NAME) exactly like a `Dockerfile`, then a block runs in it.  Explicit
  # `.build` prereq (run does not auto-build, mirroring Dockerfile).
  prog = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "from cmk import container\n"
    "container built(entrypoint=sh)(|\n  FROM alpine:3.21\n  RUN echo baked-in-image > /marker\n|)\n"
    "__main__: built.build\n"
    "  (| echo MERGE-OK:; cat /marker |) in built\n"
  )
  p = REPO / ".tmp.container_build.cmk"
  p.write_text(prog)
  try:
    r = subprocess.run(
      [str(COMPOSE), "cmk", "run", str(p)],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=300,
    )
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "MERGE-OK" in out and "baked-in-image" in out, out[-1500:]
  finally:
    p.unlink(missing_ok=True)
