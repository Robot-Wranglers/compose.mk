"""End-to-end for the callform-trailer channels (demos/cmk/banana-callforms.cmk).

A callform is a name with trailers, each a distinct bracket / channel that
composes order-free:

    (args)   -> arguments        [stream] -> stdin/filter      {env} -> environment

This demo consolidates the two trailer channels that the compile-level suites
already pin at the LOWERING level -- this file adds the RUNTIME proof that the
lowered command actually behaves:

  * {env}  -- test_callform_cmk.py asserts the lowering
             (`cmk.f{e=v}` -> `e='v' $(call f)`, and the target/multi-var/
             quoted-value/order-free/no-collision cases).  Here we prove the
             env prefix REACHES a running recipe (sub-make) and a macro.
  * [stream] at compile time -- test_banana_cmk.py::test_stream_trailer_* pins
             `name(| filter |)[S]` -> `name := $(shell S | bash <block>)`.  Here
             we prove the block actually filtered the stream AT PARSE and the
             value is available at runtime.
  * ⬥name codegen / phase-polymorphism -- test_blockref_cmk.py pins the `⬥`
             glyph lowering + FD/file plumbing.  Here we prove a parse-time
             codegen include produces real targets, and one block runs in BOTH
             phases (parse `:=` and a live recipe).

Marked `unit` (fast, no docker).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-callforms.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "banana-callforms.cmk"


def _run(*targets, timeout=90):
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


# --- {env} channel: the env prefix reaches the RUNNING command --------------


def test_env_channel_delivers_to_recipe():
  # `this.env.probe{WHO=world}` -- the sub-make's recipe must actually SEE WHO=world
  # (GREETING left unset).  This is the runtime face of test_callform_cmk.py's
  # compile-level `e='v' ${make} f` lowering assertion.
  r, out = _run("demo.env")
  assert r.returncode == 0, out
  assert "WHO=[world] GREETING=[unset]" in out


def test_env_channel_multi_var():
  # several vars at once: `{WHO=all GREETING=yo}` -- both land in the recipe env.
  r, out = _run("demo.env")
  assert r.returncode == 0, out
  assert "WHO=[all] GREETING=[yo]" in out


def test_env_composes_order_free_with_stream():
  # `this.stdin.probe{GREETING=hello}[echo world]` -- {env} supplies GREETING,
  # [stream] supplies stdin; assembled STREAM | ENV command -> "hello world".
  r, out = _run("demo.env")
  assert r.returncode == 0, out
  assert "hello world" in out


def test_env_channel_on_macro():
  # `cmk.say.macro{WHO=macroland}` -- {env} prefixes what $(call ..) expands to,
  # and the deferred `sh -c` reads WHO at runtime.
  r, out = _run("demo.env")
  assert r.returncode == 0, out
  assert "macro sees WHO=macroland" in out


# --- [stream] at COMPILE time: the block filtered the stream at parse --------


def test_comptime_stream_filter():
  # shout(| tr a-z A-Z |)[echo hello world] filtered its stream AT PARSE; the
  # recipe only prints the already-computed value.
  r, out = _run("demo.streams")
  assert r.returncode == 0, out
  assert "HELLO WORLD" in out


def test_comptime_stream_producer():
  # banner(| .. |)[] -- an empty stream is a producer (block runs with no input).
  r, out = _run("demo.streams")
  assert r.returncode == 0, out
  assert "COMPOSE.MK" in out


def test_comptime_stream_compose():
  # lines(| wc -l | tr -d ' ' |)[printf 'alpha\nbeta\ngamma\n'] -> 3 (three lines,
  # counted and whitespace-stripped at parse).
  r, out = _run("demo.streams")
  assert r.returncode == 0, out
  # the "1 compose" log line carries the computed count 3
  assert any("compose" in ln and "3" in ln for ln in out.splitlines()), out


# --- codegen + phase-polymorphism -------------------------------------------


def test_comptime_codegen_include():
  # the rules(| .. |) block emits `x:/y:/z:` targets at parse (⬥rules into a file,
  # then include); running them proves the generated recipes exist.
  r, out = _run("demo.streams")
  assert r.returncode == 0, out
  for w in ("built-x", "built-y", "built-z"):
    assert w in out, f"{w} missing -- codegen include did not produce the target\n{out}"


def test_phase_polymorphism_both_phases():
  # the SAME up(| tr a-z A-Z |) block runs at PARSE (COMPILED := $(shell .. | bash ⬥up))
  # and again at RUNTIME (echo 'at runtime' | bash ⬥up) -- one noun, two phases.
  r, out = _run("demo.streams")
  assert r.returncode == 0, out
  assert "AT COMPILE TIME" in out  # parse-phase capture
  assert "AT RUNTIME" in out  # runtime-phase live run
