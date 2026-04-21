"""Isolation tests for the `Loggable` protocol (compose.mk core; demos/cmk/loggable.cmk).

`Loggable` is a concretized mixin on `Named`: carrying `bases=Loggable` stamps a name-bound
`.log` onto every instance, plus the `.log.warn`/`.log.error`/`.log.debug` severity ladder.  Each
level bakes the instance identity at construction and delegates to the themed core loggers
(`log`/`log.warn`/`log.error`/`log.trace`), which supply the running-target header.  This
is the additive first step of TODO-loggable-protocol.md: the protocol lands with zero churn to the
existing `log.*` surface, verified here in isolation before any rename or call-site migration.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("loggable.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# a plain conformer: bases=Loggable, empty body.  Instances gain the logger by inheritance.
KIND = "cmk.class widget(bases=Loggable)[|\n  '''probe'''\n|]\nwidget alice(| |)\nwidget bob(| |)\n"


def _run(tmp_path, src, goal=None, env=None):
  f = tmp_path / "lg.cmk"
  f.write_text(src)
  argv = [str(COMPOSE), "cmk", "run", str(f)] + ([goal] if goal else [])
  return subprocess.run(
    argv,
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
    env=env,
  )


def test_conformer_is_loggable_and_named(tmp_path):
  # bases=Loggable makes the instance is-a Loggable AND (transitively) is-a Named.
  p = _run(
    tmp_path,
    KIND + "probe:\n"
    "\t$(info ISA_L=[$(call isinstance,alice,Loggable)] ISA_N=[$(call isinstance,alice,Named)])\n",
    goal="probe",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "ISA_L=[1]" in out, out
  assert "ISA_N=[1]" in out, out


def test_log_stamps_instance_identity(tmp_path):
  # bare .log(msg) logs the message under the instance name, via the delegated core logger.
  p = _run(
    tmp_path,
    KIND + "go:\n\talice.log(hello from the instance)\n",
    goal="go",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "alice" in out, out
  assert "hello from the instance" in out, out


def test_severity_ladder_dispatches(tmp_path):
  # multi-level dotted smart-send: alice.log.warn(..)/.error(..) reach .log.warn.__call__ etc, each
  # routed to its own themed core logger (distinct glyphs: warn yellow, error red).
  p = _run(
    tmp_path,
    KIND + "go:\n"
    "\talice.log.warn(a warning happened)\n"
    "\talice.log.error(an error happened)\n",
    goal="go",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "a warning happened" in out, out
  assert "an error happened" in out, out
  assert "⚠" in out, out  # warn glyph
  assert "\U0001f6c7" in out, out  # error glyph


def test_per_instance_identity(tmp_path):
  # each instance bakes its OWN identity at construction; bob's line names bob, not alice.
  p = _run(
    tmp_path,
    KIND + "go:\n\tbob.log(line under bob)\n",
    goal="go",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "bob" in out, out
  assert "alice" not in out.split("line under bob")[0].split("\n")[-1], out


def test_stamped_member_bakes_identity_defers_args(tmp_path):
  # the stamped macro fixes the identity (alice) at construction but leaves ${__args__} deferred.
  p = _run(
    tmp_path,
    KIND + "probe:\n\t$(info V=[$(value alice.log.__call__)])\n",
    goal="probe",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "$(call log,alice ${sep} ${__args__})" in out, out


def test_debug_is_trace_gated(tmp_path):
  # .log.debug delegates to the TRACE-gated core logger: silent at TRACE=0, emitted at TRACE=1.
  src = KIND + "go:\n\talice.log.debug(a debug detail)\n"
  off = _run(tmp_path, src, goal="go")
  assert off.returncode == 0, off.stdout + off.stderr
  assert "a debug detail" not in (off.stdout + off.stderr)

  import os

  on = _run(tmp_path, src, goal="go", env={**os.environ, "TRACE": "1"})
  assert on.returncode == 0, on.stdout + on.stderr
  assert "a debug detail" in (on.stdout + on.stderr)


def test_demo_runs(tmp_path):
  # the shipped isolation demo runs clean end to end.
  p = subprocess.run(
    [str(REPO / "demos" / "cmk" / "loggable.cmk")],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "info line" in out, out
  assert "warning line" in out, out
  assert "error line" in out, out
