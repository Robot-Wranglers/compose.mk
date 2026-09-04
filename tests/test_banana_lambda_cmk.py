"""End-to-end for the RECIPE-level typed block (demos/cmk/banana-lambda.cmk).

A recipe block `<machine>(| code |){env}(args)` is hoisted to a module
`define __lambda_N` and routed to the machine's `.__call__` as a blockref, run
through its entrypoint (env-prefix + positional args).  The demo uses
`host.native.sh`, so it proves the whole hoist -> route -> execute path WITHOUT
docker.  (A bare anonymous `(| .. |){env}` -- no machine -- is reserved.)

Marked `unit` (fast, no docker).  Companion to the compile-level coverage
(`test_recipe_ctor_*` / `test_anon_callform_is_reserved`) in test_banana_cmk.py.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-lambda.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "banana-lambda.cmk"


def _run(*targets, timeout=120):
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


def test_demo_runs_clean():
  r, out = _run()
  assert r.returncode == 0, out


def test_plain_block_lifts_and_runs():
  # a bare inline block is hoisted to a define and run in place via the sh runner.
  r, out = _run("demo.plain")
  assert r.returncode == 0, out
  assert "hello from a hoisted inline block" in out


def test_env_channel_reaches_the_block():
  # `{WHO=world}` lands in the dispatch env, so the lifted block reads $WHO.
  r, out = _run("demo.env")
  assert r.returncode == 0, out
  assert "greetings, world" in out


def test_two_blocks_lift_independently():
  # two anonymous blocks in one recipe -> two distinct lifts, each its own env.
  r, out = _run("demo.two")
  assert r.returncode == 0, out
  assert "first: one" in out and "second: two" in out


def test_recipe_level_capture_runs():
  # `LHS <- (| body |)` runs the lifted block at recipe time and captures its
  # stdout into a shell var used by a later line.
  r, out = _run("demo.capture")
  assert r.returncode == 0, out
  assert "got: hello from a captured block" in out


def test_cooked_capture_runs():
  # `LHS <- [| body |]` cooks the interior (this.compute -> ${make} compute),
  # make-expands + runs it at recipe time, and captures the output.
  r, out = _run("demo.cooked.capture")
  assert r.returncode == 0, out
  assert "cooked capture: computed-42" in out
