"""Unit tests for the flux.* control-flow / algebra targets.

flux.* is mostly exit-code composition: the bare primitives log to stderr,
so their stdout is empty and behavior is asserted via the return code. A
few targets (flux.echo, flux.map, flux.each, flux.if.then) are identity/map
helpers with deterministic stdout.

As in test_unit_streams, expected values encode *intended* behavior and
known defects are pinned with xfail. Note: a failing target surfaces as
make's exit code 2 (not 1), so failure is asserted with ``not r.ok``.
"""

import pytest

pytestmark = pytest.mark.unit


# (target, stdin, expected_stdout) — identity/map helpers with clean stdout.
STDOUT_CASES = [
  ("flux.echo/hello", "", "hello\n"),
  ("flux.echo/a,b,c", "", "a,b,c\n"),  # echoes the whole arg verbatim
  ("flux.map/flux.echo,hello,world", "", "hello\nworld\n"),
  ("flux.for.each/flux.echo,hello,world", "", "hello\nworld\n"),
  ("flux.each/flux.echo", "one\ntwo", "one\ntwo\n"),
  # if.then runs the 2nd target iff the 1st succeeds (else nothing).
  ("flux.if.then/flux.ok,flux.echo/THEN", "", "THEN\n"),
  ("flux.if.then/flux.fail,flux.echo/THEN", "", ""),
  # if.then.else dispatches the matching branch (clean when the condition
  # target is silent, e.g. flux.noop).
  ("flux.if.then.else/flux.noop,flux.echo/T,flux.echo/E", "", "T\n"),
]


@pytest.mark.parametrize(
  "target,stdin,expected",
  STDOUT_CASES,
  ids=[f"{t}::{s!r}" for t, s, _ in STDOUT_CASES],
)
def test_flux_stdout(cmk, target, stdin, expected):
  r = cmk(target, stdin=stdin)
  assert r.ok, f"{target} exited {r.returncode}; stderr:\n{r.stderr}"
  assert r.stdout == expected


# Targets expected to succeed (exit 0).
OK_CASES = [
  "flux.ok",
  "flux.noop",
  "flux.negate/flux.fail",
  "flux.and/flux.ok,flux.ok",
  "flux.or/flux.fail,flux.ok",
  "flux.retry/2/flux.ok",
  "flux.try.except.finally/flux.fail,flux.ok,flux.ok",
  "flux.try.except/flux.fail,flux.ok",
  "flux.try.finally/flux.ok,flux.ok",
]


@pytest.mark.parametrize("target", OK_CASES)
def test_flux_succeeds(cmk, target):
  r = cmk(target)
  assert r.ok, f"{target} should exit 0 but got {r.returncode};\n{r.stderr}"


# Targets expected to fail (non-zero exit; make reports 2).
FAIL_CASES = [
  "flux.fail",
  "flux.negate/flux.ok",
  "flux.and/flux.ok,flux.fail",
  "flux.or/flux.fail,flux.fail",
  "flux.retry/2/flux.fail",
  "flux.try.except.finally/flux.fail,flux.fail,flux.ok",
]


@pytest.mark.parametrize("target", FAIL_CASES)
def test_flux_fails(cmk, target):
  r = cmk(target)
  assert not r.ok, f"{target} should exit non-zero but got 0"


# --- Known bugs (surfaced by these tests) -------------------------------


@pytest.mark.xfail(
  reason=(
    "flux.if.then.else redirects the condition target with "
    "`2>&1 > /dev/null` (wrong order), leaking its stderr onto "
    "stdout instead of discarding it (compose.mk:2968)"
  ),
  strict=False,
)
def test_if_then_else_does_not_leak_condition_output(cmk):
  r = cmk("flux.if.then.else/flux.ok,flux.echo/T,flux.echo/E")
  assert r.ok, r.stderr
  assert r.stdout == "T\n"
