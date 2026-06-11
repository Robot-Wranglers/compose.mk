"""Signals / supervisor / pre-post-hook path (the interpreter entrypoint).

This is the `mk.interpret` orchestration: the bash-wrapper installs a signal
supervisor (CMK_SUPERVISOR=1), rewrites CLI goals into
`flux.pre/<t> <t> flux.post/<t>` (`.awk.rewrite.targets.maybe`), and the
`mk.yield -> mk.interrupt -> mk.supervisor.*` chain transfers control. None of
it fires under plain `make -f` (library mode) -- only via the interpreter.

The shared `cmk`/`docker_cmk` fixtures deliberately disable this whole path
(BASE_ENV pins CMK_SUPERVISOR=0 + CMK_DISABLE_HOOKS=1), so these tests drive a
seeded copy of compose.mk directly with supervisor on / hooks enabled, in their
own session (start_new_session=True) so the supervisor's self-SIGINT stays
scoped to the child and never touches the test runner.

Behavioral contract pinned here (per docs/signals.md "Pre & Post Hooks"):
  * `<target>.pre` / `<target>.post` fire around `<target>`, in order;
  * hooking a builtin (`flux.ok.pre`) works;
  * `CMK_DISABLE_HOOKS=1` suppresses hooks;
  * a target with no hooks runs clean (the no-hook fast path);
  * an empty CLI resolves the default goal (`__main__` via mk.get/.DEFAULT_GOAL);
  * hooks do NOT fire under `make -f` (library mode).

This is the regression net for the interpret-orchestration perf work (collapsing
redundant supervisor sub-makes): every interpret run here exercises
`mk.yield`/`mk.interrupt`/`mk.supervisor.pid`, so a break in that chain fails
these.
"""

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest

pytestmark = pytest.mark.integration

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"

# Supervisor ON, hooks ENABLED (the inverse of BASE_ENV), deterministic + quiet.
INTERP_ENV = {
  "NO_COLOR": "1",
  "CMK_SUPERVISOR": "1",
  "CMK_DISABLE_HOOKS": "0",
  "CMK_INTERNAL": "1",
  "TERM": "dumb",
  "TRACE": "0",
  "GITHUB_ACTIONS": "false",
}


@dataclass
class Result:
  stdout: str
  stderr: str
  returncode: int

  @property
  def ok(self) -> bool:
    return self.returncode == 0


def _interp(tmp_path, body, *targets, env=None, library=False, timeout=60):
  """Run `body` as a makefile through the interpreter entrypoint.

  Seeds a compose.mk copy in tmp_path (so `./compose.mk` resolves and the
  `.tmp.*`/combined-file scratch lands in tmp_path, not the repo), writes the
  user program, and invokes it. ``library=True`` instead runs it via plain
  ``make -f`` (no wrapper) to prove hooks are interpreter-only.
  """
  prog = tmp_path / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  user = tmp_path / "prog.mk"
  if library:
    # library mode needs an explicit include to pull in compose.mk
    user.write_text("include compose.mk\n" + body)
    argv = ["make", "-f", "prog.mk", *targets]
  else:
    user.write_text(body)
    argv = ["./compose.mk", "mk.interpret", "prog.mk", *targets]
  merged = {**os.environ, **INTERP_ENV, **(env or {})}
  proc = subprocess.Popen(
    argv,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=str(tmp_path),
    env=merged,
    start_new_session=True,
  )
  try:
    out, err = proc.communicate(input="", timeout=timeout)
  except subprocess.TimeoutExpired:
    proc.kill()
    out, err = proc.communicate()
    raise
  return Result(out, err, proc.returncode)


HOOKED = (
  "main_target.pre:; @echo PRE\n"
  "main_target:; @echo MAIN\n"
  "main_target.post:; @echo POST\n"
  "nohook:; @echo PLAIN\n"
  "flux.ok.pre:; @echo BUILTIN-HOOK\n"
  "__main__:; @echo DEFAULTGOAL\n"
)


def test_pre_post_hooks_fire_in_order(tmp_path):
  # The headline feature: <t>.pre, <t>, <t>.post fire around the CLI target.
  r = _interp(tmp_path, HOOKED, "main_target")
  assert r.ok, r.stderr
  lines = [ln for ln in r.stdout.splitlines() if ln in ("PRE", "MAIN", "POST")]
  assert lines == ["PRE", "MAIN", "POST"], r.stdout


def test_builtin_hook_fires(tmp_path):
  # Hooks attach to compose.mk builtins too (flux.ok.pre before flux.ok).
  r = _interp(tmp_path, HOOKED, "flux.ok")
  assert r.ok, r.stderr
  assert "BUILTIN-HOOK" in r.stdout


def test_hooks_disabled_suppresses_them(tmp_path):
  # CMK_DISABLE_HOOKS=1 -> the target runs, the hooks do not.
  r = _interp(tmp_path, HOOKED, "main_target", env={"CMK_DISABLE_HOOKS": "1"})
  assert r.ok, r.stderr
  assert "MAIN" in r.stdout
  assert "PRE" not in r.stdout and "POST" not in r.stdout


def test_target_without_hooks_runs_clean(tmp_path):
  # The no-hook fast path: a target with no .pre/.post still runs, exits 0, and
  # emits no stray hook output. (Guards the hook-gating optimization.)
  r = _interp(tmp_path, HOOKED, "nohook")
  assert r.ok, r.stderr
  assert "PLAIN" in r.stdout
  assert "PRE" not in r.stdout and "POST" not in r.stdout


def test_empty_cli_resolves_default_goal(tmp_path):
  # No target on the CLI -> mk.__main__ resolves & runs the default goal
  # (__main__) via mk.get/.DEFAULT_GOAL. (Guards the default-goal optimization.)
  r = _interp(tmp_path, HOOKED)
  assert r.ok, r.stderr
  assert "DEFAULTGOAL" in r.stdout


def test_hooks_do_not_fire_in_library_mode(tmp_path):
  # Documented limitation: `make -f` bypasses the wrapper, so no hooks fire.
  r = _interp(tmp_path, HOOKED, "main_target", library=True)
  assert r.ok, r.stderr
  assert "MAIN" in r.stdout
  assert "PRE" not in r.stdout and "POST" not in r.stdout


def test_hook_in_included_file_fires(tmp_path):
  # A hook can live in an `include`d file, not just the main program -- the
  # existence check follows includes. This is the edge case any "skip injection
  # when the main file has no hooks" optimization MUST NOT regress.
  (tmp_path / "hooks.mk").write_text(
    "main_target.pre:; @echo PRE-FROM-INCLUDE\n"
  )
  body = "include hooks.mk\nmain_target:; @echo MAIN\n__main__:; @echo D\n"
  r = _interp(tmp_path, body, "main_target")
  assert r.ok, r.stderr
  assert "PRE-FROM-INCLUDE" in r.stdout, r.stdout
  assert "MAIN" in r.stdout


def test_default_path_skips_internal_dispatcher_hook(tmp_path):
  # Perf optimization (intentional behavior): on an empty CLI the synthesized
  # default `mk.__main__` is NOT hook-rewritten, so a hook on the *internal*
  # default-goal dispatcher (`mk.__main__.pre`) does not fire -- the user's real
  # default goal still runs (it always ran hook-free via recursive `${make}`).
  # Explicit-target hooks are unaffected (test_pre_post_hooks_fire_in_order).
  body = (
    "mk.__main__.pre:; @echo INTERNAL-MAIN-PRE\n__main__:; @echo USER-MAIN\n"
  )
  r = _interp(tmp_path, body)
  assert r.ok, r.stderr
  assert "USER-MAIN" in r.stdout
  assert "INTERNAL-MAIN-PRE" not in r.stdout, r.stdout


def test_at_exit_handler_runs(tmp_path):
  # CMK_AT_EXIT_TARGETS fires via mk.supervisor.exit after the main pipeline.
  # A successful goal + at-exit handler now exits 0 (the wrapper no longer adopts
  # mk.supervisor.exit's own status -- see the exact-exit-code work below).
  body = HOOKED + "myexit:; @echo AT-EXIT-RAN\n"
  r = _interp(tmp_path, body, "nohook", env={"CMK_AT_EXIT_TARGETS": "myexit"})
  assert r.ok, r.stderr  # success goal + handler -> clean 0 exit
  assert "PLAIN" in r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout


def test_at_exit_handler_runs_even_when_main_fails(tmp_path):
  # The guarantee demos rely on for cleanup: mk.supervisor.exit runs the at-exit
  # target "regardless of whether the pipeline was successful". Here the CLI goal
  # FAILS, yet the handler still fires (and the run reports nonzero).
  body = HOOKED + "boom:; @echo MAIN-RAN ; false\nmyexit:; @echo AT-EXIT-RAN\n"
  r = _interp(tmp_path, body, "boom", env={"CMK_AT_EXIT_TARGETS": "myexit"})
  assert "MAIN-RAN" in r.stdout, r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout  # fired despite the failure
  assert not r.ok  # a failed main pipeline still surfaces a nonzero exit


def test_at_exit_multiple_targets_all_run(tmp_path):
  # CMK_AT_EXIT_TARGETS is a space-separated list (docs/signals.md): every named
  # target runs at exit, in order.
  body = HOOKED + "exit1:; @echo EXIT-ONE\nexit2:; @echo EXIT-TWO\n"
  r = _interp(
    tmp_path, body, "nohook", env={"CMK_AT_EXIT_TARGETS": "exit1 exit2"}
  )
  assert "PLAIN" in r.stdout
  assert "EXIT-ONE" in r.stdout and "EXIT-TWO" in r.stdout, r.stdout


def test_at_exit_declared_in_file_via_export(tmp_path):
  # The idiomatic in-program form (cf. demos/cmk/exceptions.cmk): the makefile
  # itself `export`s CMK_AT_EXIT_TARGETS, so no caller env is needed.
  body = (
    "export CMK_AT_EXIT_TARGETS=myexit\n"
    + HOOKED
    + "myexit:; @echo AT-EXIT-RAN\n"
  )
  r = _interp(tmp_path, body, "nohook")
  assert "PLAIN" in r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout


def test_at_exit_append_preserves_existing(tmp_path):
  # A program should `+=` (append) its handler rather than overriding, so a
  # caller-provided CMK_AT_EXIT_TARGETS survives (cf. demos/cmk/exceptions.cmk).
  # With a caller value in the env, the in-file `+=` adds to it -> BOTH run.
  body = (
    "export CMK_AT_EXIT_TARGETS += progexit\n"
    + HOOKED
    + "progexit:; @echo PROG-EXIT\ncallerexit:; @echo CALLER-EXIT\n"
  )
  r = _interp(
    tmp_path, body, "nohook", env={"CMK_AT_EXIT_TARGETS": "callerexit"}
  )
  assert "PLAIN" in r.stdout
  assert "CALLER-EXIT" in r.stdout, r.stdout  # caller's handler not clobbered
  assert "PROG-EXIT" in r.stdout, r.stdout  # program's handler also ran


# --- exact exit-code propagation (record-and-continue) -----------------------
# GNU make collapses any recipe failure to exit 2 at every sub-make boundary.
# `mk.exit.code/<N>` records the EXACT code out-of-band (the supervisor pidfile)
# and fails normally, so the make stack unwinds (finally/cleanup arms still run)
# and the bash supervisor wrapper -- the only non-flattening exit point -- delivers
# <N> to the OS. These are the first tests to assert SPECIFIC nonzero codes; they
# must use `_interp` (CMK_SUPERVISOR=1), since the channel needs the supervisor.

# Minimal program exercising the exact-code paths.
EXITBODY = (
  "rerr:; @$(call mk.exit.code,42)\n"  # macro form
  "fin:; @echo SENTINEL-FINALLY\n"
  "okx:; @echo OKX\n"
  "boom7:; @echo MAIN ; exit 7\n"
  "atx:; @echo AT-EXIT-SENTINEL\n"
  # hand-rolled swallow that must clear the recorded code to recover:
  "handled:; @${make} rerr </dev/null || { echo HANDLED ; ${make} mk.exit.clear ; } ; echo CONTINUED\n"
  "leaked:; @${make} rerr </dev/null || true ; echo CONTINUED\n"
  "__main__:; @echo D\n"
)


def test_exit_code_exact_record_and_continue(tmp_path):
  # The headline: the top-level process exits with the EXACT code, not make's 2.
  r = _interp(tmp_path, EXITBODY, "mk.exit.code/42")
  assert r.returncode == 42, (r.returncode, r.stderr)


def test_exit_code_macro_form(tmp_path):
  # `$(call mk.exit.code,42)` inline inside a recipe delivers the same exact code.
  r = _interp(tmp_path, EXITBODY, "rerr")
  assert r.returncode == 42, (r.returncode, r.stderr)


def test_exit_code_finally_still_runs(tmp_path):
  # The record-and-continue payoff: an unrecovered failure carrying an exact code
  # STILL runs the `finally` arm, and the exact code survives to the top.
  r = _interp(tmp_path, EXITBODY, "flux.try.except.finally/rerr,flux.fail,fin")
  assert r.returncode == 42, (r.returncode, r.stderr)
  assert "SENTINEL-FINALLY" in r.stdout, r.stdout  # finally ran


def test_exit_code_recovery_clears(tmp_path):
  # If the `except` arm RECOVERS, the pending exact code is cleared -> exit 0
  # (no stale leak), and finally still runs.
  r = _interp(tmp_path, EXITBODY, "flux.try.except.finally/rerr,flux.ok,fin")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "SENTINEL-FINALLY" in r.stdout, r.stdout


def test_exit_code_ordinary_failure_still_two(tmp_path):
  # Backward-compat: a plain failure with no mk.exit.code still flattens to 2.
  r = _interp(tmp_path, EXITBODY, "boom7")
  assert r.returncode == 2, (r.returncode, r.stderr)
  assert "MAIN" in r.stdout


def test_exit_code_success_zero_no_stale(tmp_path):
  # Success exits 0 and leaves no supervisor pidfile behind.
  r = _interp(tmp_path, EXITBODY, "okx")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "OKX" in r.stdout
  assert not list(tmp_path.glob(".tmp.mk.super.*")), (
    "stale pidfile left behind"
  )


def test_exit_code_with_at_exit_handler(tmp_path):
  # An exact exit code and the CMK_AT_EXIT_TARGETS handler coexist: handler runs,
  # and the exact code is still delivered.
  r = _interp(
    tmp_path, EXITBODY, "mk.exit.code/42", env={"CMK_AT_EXIT_TARGETS": "atx"}
  )
  assert r.returncode == 42, (r.returncode, r.stderr)
  assert "AT-EXIT-SENTINEL" in r.stdout, r.stdout


def test_exit_clear_recovers_in_custom_handler(tmp_path):
  # A hand-rolled swallow (`|| { ... }`) only fully recovers if it also calls
  # `mk.exit.clear` to retract the recorded code -> exit 0.
  r = _interp(tmp_path, EXITBODY, "handled")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "HANDLED" in r.stdout and "CONTINUED" in r.stdout, r.stdout


def test_exit_code_leaks_without_clear(tmp_path):
  # Counterpoint: a bare `|| true` swallow continues execution but does NOT clear
  # the recorded code, so it still reaches the top (the sharp edge mk.exit.clear fixes).
  r = _interp(tmp_path, EXITBODY, "leaked")
  assert "CONTINUED" in r.stdout, (
    r.stdout
  )  # execution continued past the swallow
  assert r.returncode == 42, (
    r.returncode,
    r.stderr,
  )  # ...yet the code leaked out
