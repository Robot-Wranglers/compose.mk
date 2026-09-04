"""Sandbox partition: a parallel copy of the `__hosted__` mechanism (same content-addressed
cache + `lang.transpile` pipeline + makefile-remaking), keyed on `define __sandbox__`.  It is
a lab bench for the recurring dedent/cook/docstring hazards -- experimental CMK-lang goes here
and rides the REAL compiler, without risking the load-bearing hosted partition.

The load-bearing contract these tests pin is the ISOLATION: the sandbox is OPT-IN (inert unless
a `sandbox.*` goal is requested or `CMK_SANDBOX` is truthy), so an unstable experiment can never
halt a normal `make <other>` parse -- the exact property that makes it safe to debug in.  Pure
local make, no docker -- exercised from a vanilla makefile that only `include`s compose.mk.
"""

from pathlib import Path

import pytest

# The sandbox is a no-docker lab bench for dedent/cook/docstring lowering hazards that
# rides the REAL compiler; several cases assert on `.compiled` transpile text.  It must
# run in the `compiler` gate, not just `unit` -- `unit`-only hid lowering regressions.
pytestmark = [pytest.mark.unit, pytest.mark.compiler]

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrapper(tmp_path, main=None):
  # Pre-create ./.cmk so the cache lands in the (writable, project-local) modules dir under
  # tmp_path rather than the real ~/.cache -- mirrors a real project and keeps the test hermetic.
  (tmp_path / ".cmk").mkdir(exist_ok=True)
  mk = tmp_path / "Makefile"
  body = "include %s\n" % COMPOSE_MK
  if main:
    body += "__main__: %s\n" % main
  mk.write_text(body)
  return mk


def _sandbox_caches(tmp_path):
  d = tmp_path / ".cmk"
  return sorted(d.glob(".tmp.sandbox.*.mk")) if d.exists() else []


def test_sandbox_selftest_reachable_when_requested(cmk, tmp_path):
  # A `sandbox.*` goal opts the partition in: the cache builds and the CMK-lang
  # `sandbox.selftest` (authored in `define __sandbox__`) is reachable and runs.
  r = cmk("sandbox.selftest", makefile=_wrapper(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr
  both = r.stdout + r.stderr
  assert "sandbox partition is live" in both, both
  assert "ok" in r.stdout, r.stdout
  assert len(_sandbox_caches(tmp_path)) == 1, _sandbox_caches(tmp_path)


def test_sandbox_inert_by_default(cmk, tmp_path):
  # A NON-sandbox goal with no CMK_SANDBOX must NOT build (or even parse) the sandbox cache:
  # the isolation that lets a broken experiment sit in `__sandbox__` without touching normal ops.
  r = cmk(
    "hosted.selftest",
    makefile=_wrapper(tmp_path, main="hosted.selftest"),
    cwd=tmp_path,
  )
  assert r.ok, r.stderr
  assert "hosted partition is live" in (r.stdout + r.stderr), r.stderr
  assert _sandbox_caches(tmp_path) == [], "sandbox built despite no opt-in"


def test_sandbox_env_flag_activates(cmk, tmp_path):
  # `CMK_SANDBOX` truthy opts the partition in even for a non-sandbox goal (the always-on switch).
  r = cmk(
    "hosted.selftest",
    makefile=_wrapper(tmp_path, main="hosted.selftest"),
    cwd=tmp_path,
    env={"CMK_SANDBOX": "1"},
  )
  assert r.ok, r.stderr
  assert len(_sandbox_caches(tmp_path)) == 1, "CMK_SANDBOX=1 did not build the sandbox"


# --- The injection harness (the `sandbox` fixture): inject arbitrary CMK-lang per test, run it
#     through the real compiler, and assert on runtime behavior OR the lowered makefile text.
#     These double as the worked examples for writing new probe tests. ------------------------


def test_inject_plain_target(sandbox):
  # The simplest injection: a bare make target, run and observed.
  r = sandbox.run("probe:\n\t@echo INJECTED_OK", goal="probe")
  assert r.ok, r.output
  assert "INJECTED_OK" in r.stdout, r.output


def test_inject_banana_form(sandbox):
  # A CMK-lang banana-form target (the compiler-heavy path this bench exists for): a docstring
  # plus a `cmk.log(..)` callform must lower and run.
  body = "probe:\n  '''banana form docstring'''\n  cmk.log(banana works)\n  echo done"
  r = sandbox.run(body, goal="probe")
  assert r.ok, r.output
  assert "banana works" in r.output, r.output
  assert "done" in r.stdout, r.output


@pytest.mark.docstring
def test_probe_target_docstring_lowering(sandbox):
  # Characterize the compiler: a TARGET docstring lowers to an `@#` recipe comment (not a
  # `__doc__` var, and never leaks to stdout here -- there is no recipe-injecting compiler_pre
  # stage in the sandbox).  Assert on `.compiled` (the transpiled cache), no target run needed.
  r = sandbox.compile("probe:\n  '''hello docstring'''\n  echo hi")
  assert r.compiled is not None, r.output
  assert "@# hello docstring" in r.compiled, r.compiled
  assert "'''" not in r.compiled, r.compiled  # the triple-quotes are consumed, not passed through


def test_broken_injection_is_non_fatal(sandbox):
  # A malformed snippet (here an unbalanced banana) must NOT halt: the build warns + skips, so
  # `.compiled` is None and the precise compiler error is surfaced on stderr -- the clean debug
  # signal the bench is for.
  r = sandbox.compile("cmk.class busted(|\n  x := 1")
  assert r.compiled is None, r.compiled
  assert "cmk:" in r.stderr, r.output
  assert "unbalanced banana" in r.stderr, r.output


@pytest.mark.docstring
def test_unterminated_target_docstring_faults(sandbox):
  # The compiler was HARDENED (exactly the flip the old CHARACTERIZATION here predicted): an
  # UNTERMINATED triple-quoted docstring is now REJECTED as a GRAMMAR fault -- no cache promoted,
  # the run FAILS -- instead of the old silent-recipe-swallow quirk (rc 0, commands vanished).
  body = "probe:\n  '''oops i forgot to close this docstring\n  echo MARKER_SHOULD_VANISH"
  r = sandbox.run(body, goal="probe")
  assert not r.ok, r.output                                  # rejected, not a silent "success"
  assert "unterminated triple-quoted" in r.stderr, r.output  # the moduledoc diagnostic
  assert "MARKER_SHOULD_VANISH" not in r.stdout, r.output    # the swallowed command never ran
