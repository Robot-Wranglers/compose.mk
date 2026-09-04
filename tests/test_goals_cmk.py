"""End-to-end for the named-lift form `goal NAME = <expr>` (demos/cmk/goals.cmk).

`goal NAME = <target-expr>` lifts a make goal into a first-class value: it binds
`NAME := <expr>` (the reify -- so `compile(goal(t)) == t`, a section of compile),
a runnable target, and registers NAME into the `__goals__` registry (which conforms
to the `registry` protocol structurally).  Because the lift is just a macro
(`goal.bind`), the demo mints one goal per stage in a caller-provided PIPELINE and
dispatches them dynamically.

Marked `unit` (fast, no docker).
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("goals.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "goals.cmk"


def _run(*targets, env=None, timeout=120):
  e = {**os.environ, **env} if env else None
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
    env=e,
  )
  return r, (r.stdout + r.stderr)


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


def test_demo_runs_clean():
  r, out = _run()
  assert r.returncode == 0, out
  # a colliding reify-target (e.g. a core stage/%) would surface here, not exit 0-clean.
  assert "command not found" not in out, out


def test_binding_lowers_to_goal_bind():
  # `goal NAME = expr` is a module-directive rewritten in the acquire stage; a comma in
  # the expr is protected from the $(call) arg-split via $(comma).
  low = _transpile("goal Deploy = flux.pipeline/a,b,c\n")
  assert "$(call goal.bind, Deploy, flux.pipeline/a$(comma)b$(comma)c)" in low, low


def test_default_pipeline_mints_and_registers():
  # the default PIPELINE mints one goal per stage, in order, into __goals__.
  r, out = _run()
  assert r.returncode == 0, out
  assert "registry __goals__ = extract transform load" in out


def test_reify_is_a_section_of_compile():
  # each minted goal reifies to the exact target-string it was bound to -- compile(lift) == id.
  r, out = _run()
  assert r.returncode == 0, out
  assert "extract reifies to phase/extract" in out
  assert "load reifies to phase/load" in out


def test_minted_goals_dispatch_dynamically():
  # __main__ dispatches whatever PIPELINE asked for -- running each minted goal runs its
  # phase/<name> target.
  r, out = _run()
  assert r.returncode == 0, out
  assert "phase extract ran" in out
  assert "phase transform ran" in out
  assert "phase load ran" in out


def test_goal_set_is_data_driven():
  # a different PIPELINE mints a different goal-set from the same code -- no hardcoded names.
  r, out = _run(env={"PIPELINE": "build test ship"})
  assert r.returncode == 0, out
  assert "registry __goals__ = build test ship" in out
  assert "ship reifies to phase/ship" in out
  assert "phase build ran" in out and "phase ship ran" in out


def test_goals_conforms_to_registry_protocol():
  # __goals__ exposes .has/.require, so it is structurally a `registry`.
  r, out = _run()
  assert r.returncode == 0, out
  assert "__goals__ conforms" in out
