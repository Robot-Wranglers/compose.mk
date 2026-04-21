"""Signals / supervisor / pre-post-hook path (the interpreter entrypoint).

This is the `mk.interpret` orchestration: the bash-wrapper installs a signal
supervisor (CMK_SUPERVISOR=1), rewrites CLI goals into
`flux.pre/<t> <t> flux.post/<t>` (`.awk.rewrite.targets.maybe`), and the
`mk.yield -> mk.interrupt -> mk.super.*` chain transfers control. None of
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
`mk.yield`/`mk.interrupt`/`mk.super.pid`, so a break in that chain fails
these.
"""

import os
import shutil
import signal
import subprocess
import time
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


def _interpret(tmp_path, body, *targets, env=None, library=False, timeout=60):
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
  r = _interpret(tmp_path, HOOKED, "main_target")
  assert r.ok, r.stderr
  lines = [ln for ln in r.stdout.splitlines() if ln in ("PRE", "MAIN", "POST")]
  assert lines == ["PRE", "MAIN", "POST"], r.stdout


def test_builtin_hook_fires(tmp_path):
  # Hooks attach to compose.mk builtins too (flux.ok.pre before flux.ok).
  r = _interpret(tmp_path, HOOKED, "flux.ok")
  assert r.ok, r.stderr
  assert "BUILTIN-HOOK" in r.stdout


def test_hooks_disabled_suppresses_them(tmp_path):
  # CMK_DISABLE_HOOKS=1 -> the target runs, the hooks do not.
  r = _interpret(tmp_path, HOOKED, "main_target", env={"CMK_DISABLE_HOOKS": "1"})
  assert r.ok, r.stderr
  assert "MAIN" in r.stdout
  assert "PRE" not in r.stdout and "POST" not in r.stdout


def test_target_without_hooks_runs_clean(tmp_path):
  # The no-hook fast path: a target with no .pre/.post still runs, exits 0, and
  # emits no stray hook output. (Guards the hook-gating optimization.)
  r = _interpret(tmp_path, HOOKED, "nohook")
  assert r.ok, r.stderr
  assert "PLAIN" in r.stdout
  assert "PRE" not in r.stdout and "POST" not in r.stdout


def test_mk_yield_transfers_control_and_skips_rest(tmp_path):
  # mk.yield hands the invocation off to another command and does NOT return -- the
  # control-transfer that demos/interpreter*.mk (and their .cmk twins) exist to show.
  # Asserted directly here on a synthetic program: the handoff command runs AND the recipe
  # line after the yield does not.  The demos rely on a trailing `this second line never
  # runs!` marker + a bare exit-code sweep; this proves the behavior independently.
  body = (
    "handoff:\n"
    "\t$(call mk.yield, echo YIELDED)\n"
    "\techo AFTER-YIELD-SHOULD-NOT-PRINT\n"
  )
  r = _interpret(tmp_path, body, "handoff")
  assert r.ok, r.stderr
  assert "YIELDED" in r.stdout, r.stdout                       # the handoff command ran
  assert "AFTER-YIELD" not in r.stdout, "recipe continued past mk.yield"  # rest was skipped


def test_empty_cli_resolves_default_goal(tmp_path):
  # No target on the CLI -> mk.__main__ resolves & runs the default goal
  # (__main__) via mk.get/.DEFAULT_GOAL. (Guards the default-goal optimization.)
  r = _interpret(tmp_path, HOOKED)
  assert r.ok, r.stderr
  assert "DEFAULTGOAL" in r.stdout


def test_hooks_do_not_fire_in_library_mode(tmp_path):
  # Documented limitation: `make -f` bypasses the wrapper, so no hooks fire.
  r = _interpret(tmp_path, HOOKED, "main_target", library=True)
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
  r = _interpret(tmp_path, body, "main_target")
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
  r = _interpret(tmp_path, body)
  assert r.ok, r.stderr
  assert "USER-MAIN" in r.stdout
  assert "INTERNAL-MAIN-PRE" not in r.stdout, r.stdout


def test_at_exit_handler_runs(tmp_path):
  # CMK_POST fires via mk.super.exit after the main pipeline.
  # A successful goal + at-exit handler now exits 0 (the wrapper no longer adopts
  # mk.super.exit's own status -- see the exact-exit-code work below).
  body = HOOKED + "myexit:; @echo AT-EXIT-RAN\n"
  r = _interpret(tmp_path, body, "nohook", env={"CMK_POST": "myexit"})
  assert r.ok, r.stderr  # success goal + handler -> clean 0 exit
  assert "PLAIN" in r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout


def test_at_exit_handler_runs_even_when_main_fails(tmp_path):
  # The guarantee demos rely on for cleanup: mk.super.exit runs the at-exit
  # target "regardless of whether the pipeline was successful". Here the CLI goal
  # FAILS, yet the handler still fires (and the run reports nonzero).
  body = HOOKED + "boom:; @echo MAIN-RAN ; false\nmyexit:; @echo AT-EXIT-RAN\n"
  r = _interpret(tmp_path, body, "boom", env={"CMK_POST": "myexit"})
  assert "MAIN-RAN" in r.stdout, r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout  # fired despite the failure
  assert not r.ok  # a failed main pipeline still surfaces a nonzero exit


def test_at_exit_multiple_targets_all_run(tmp_path):
  # CMK_POST is a space-separated list (docs/signals.md): every named
  # target runs at exit, in order.
  body = HOOKED + "exit1:; @echo EXIT-ONE\nexit2:; @echo EXIT-TWO\n"
  r = _interpret(tmp_path, body, "nohook", env={"CMK_POST": "exit1 exit2"})
  assert "PLAIN" in r.stdout
  assert "EXIT-ONE" in r.stdout and "EXIT-TWO" in r.stdout, r.stdout


def test_at_exit_declared_in_file_via_export(tmp_path):
  # The idiomatic in-program form (cf. demos/cmk/exceptions.cmk): the makefile
  # itself `export`s CMK_POST, so no caller env is needed.
  body = "export CMK_POST=myexit\n" + HOOKED + "myexit:; @echo AT-EXIT-RAN\n"
  r = _interpret(tmp_path, body, "nohook")
  assert "PLAIN" in r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout


def test_at_exit_append_preserves_existing(tmp_path):
  # A program should `+=` (append) its handler rather than overriding, so a
  # caller-provided CMK_POST survives (cf. demos/cmk/exceptions.cmk).
  # With a caller value in the env, the in-file `+=` adds to it -> BOTH run.
  body = (
    "export CMK_POST += progexit\n"
    + HOOKED
    + "progexit:; @echo PROG-EXIT\ncallerexit:; @echo CALLER-EXIT\n"
  )
  r = _interpret(tmp_path, body, "nohook", env={"CMK_POST": "callerexit"})
  assert "PLAIN" in r.stdout
  assert "CALLER-EXIT" in r.stdout, r.stdout  # caller's handler not clobbered
  assert "PROG-EXIT" in r.stdout, r.stdout  # program's handler also ran


# --- pre-pipeline (boot) handlers: CMK_PRE / mk.super.boot -------------------
# Symmetric with the CMK_POST at-exit handlers above: CMK_PRE names make-targets
# that run BEFORE the main pipeline, during the supervisor's bootloader stage.


def test_pre_handler_runs_before_main(tmp_path):
  # CMK_PRE fires via mk.super.boot, ahead of the main pipeline.
  body = "mypre:; @echo PRE-RAN\n__main__:; @echo MAIN\n"
  r = _interpret(tmp_path, body, env={"CMK_PRE": "mypre"})
  assert r.ok, r.stderr
  assert "PRE-RAN" in r.stdout, r.stdout
  assert "MAIN" in r.stdout, r.stdout
  assert r.stdout.index("PRE-RAN") < r.stdout.index("MAIN")  # before main


def test_pre_handler_failure_aborts_main_but_post_still_runs(tmp_path):
  # A FAILING pre handler gates the run: the main pipeline is skipped, but the
  # at-exit handlers still fire (like a finally), and the run reports nonzero.
  body = (
    "mypre:; @echo PRE-RAN ; false\n"
    "__main__:; @echo MAIN\n"
    "mypost:; @echo POST-RAN\n"
  )
  r = _interpret(tmp_path, body, env={"CMK_PRE": "mypre", "CMK_POST": "mypost"})
  assert not r.ok  # failed boot stage surfaces a nonzero exit
  assert "PRE-RAN" in r.stdout, r.stdout
  assert "MAIN" not in r.stdout, r.stdout  # main was skipped
  assert "POST-RAN" in r.stdout, r.stdout  # at-exit still ran


def test_pre_multiple_targets_all_run(tmp_path):
  # CMK_PRE is a space-separated list: every named target runs at boot, in order.
  body = "p1:; @echo PRE-ONE\np2:; @echo PRE-TWO\n__main__:; @echo MAIN\n"
  r = _interpret(tmp_path, body, env={"CMK_PRE": "p1 p2"})
  assert r.ok, r.stderr
  assert "PRE-ONE" in r.stdout and "PRE-TWO" in r.stdout, r.stdout
  assert r.stdout.index("PRE-ONE") < r.stdout.index("MAIN")


# --- exact exit-code propagation (record-and-continue) -----------------------
# GNU make collapses any recipe failure to exit 2 at every sub-make boundary.
# `mk.exit.code/<N>` records the EXACT code out-of-band (the supervisor pidfile)
# and fails normally, so the make stack unwinds (finally/cleanup arms still run)
# and the bash supervisor wrapper -- the only non-flattening exit point -- delivers
# <N> to the OS. These are the first tests to assert SPECIFIC nonzero codes; they
# must use `_interpret` (CMK_SUPERVISOR=1), since the channel needs the supervisor.

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
  r = _interpret(tmp_path, EXITBODY, "mk.exit.code/42")
  assert r.returncode == 42, (r.returncode, r.stderr)


def test_exit_code_macro_form(tmp_path):
  # `$(call mk.exit.code,42)` inline inside a recipe delivers the same exact code.
  r = _interpret(tmp_path, EXITBODY, "rerr")
  assert r.returncode == 42, (r.returncode, r.stderr)


def test_exit_code_finally_still_runs(tmp_path):
  # The record-and-continue payoff: an unrecovered failure carrying an exact code
  # STILL runs the `finally` arm, and the exact code survives to the top.
  r = _interpret(tmp_path, EXITBODY, "flux.try.except.finally/rerr,flux.fail,fin")
  assert r.returncode == 42, (r.returncode, r.stderr)
  assert "SENTINEL-FINALLY" in r.stdout, r.stdout  # finally ran


def test_exit_code_recovery_clears(tmp_path):
  # If the `except` arm RECOVERS, the pending exact code is cleared -> exit 0
  # (no stale leak), and finally still runs.
  r = _interpret(tmp_path, EXITBODY, "flux.try.except.finally/rerr,flux.ok,fin")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "SENTINEL-FINALLY" in r.stdout, r.stdout


def test_exit_code_ordinary_failure_still_two(tmp_path):
  # Backward-compat: a plain failure with no mk.exit.code still flattens to 2.
  r = _interpret(tmp_path, EXITBODY, "boom7")
  assert r.returncode == 2, (r.returncode, r.stderr)
  assert "MAIN" in r.stdout


def test_exit_code_success_zero_no_stale(tmp_path):
  # Success exits 0 and leaves no supervisor pidfile behind.
  r = _interpret(tmp_path, EXITBODY, "okx")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "OKX" in r.stdout
  assert not list(tmp_path.glob(".tmp.mk.super.*")), (
    "stale pidfile left behind"
  )


def test_exit_code_with_at_exit_handler(tmp_path):
  # An exact exit code and the CMK_POST handler coexist: handler runs,
  # and the exact code is still delivered.
  r = _interpret(tmp_path, EXITBODY, "mk.exit.code/42", env={"CMK_POST": "atx"})
  assert r.returncode == 42, (r.returncode, r.stderr)
  assert "AT-EXIT-SENTINEL" in r.stdout, r.stdout


def test_exit_clear_recovers_in_custom_handler(tmp_path):
  # A hand-rolled swallow (`|| { ... }`) only fully recovers if it also calls
  # `mk.exit.clear` to retract the recorded code -> exit 0.
  r = _interpret(tmp_path, EXITBODY, "handled")
  assert r.returncode == 0, (r.returncode, r.stderr)
  assert "HANDLED" in r.stdout and "CONTINUED" in r.stdout, r.stdout


def test_exit_code_leaks_without_clear(tmp_path):
  # Counterpoint: a bare `|| true` swallow continues execution but does NOT clear
  # the recorded code, so it still reaches the top (the sharp edge mk.exit.clear fixes).
  r = _interpret(tmp_path, EXITBODY, "leaked")
  assert "CONTINUED" in r.stdout, (
    r.stdout
  )  # execution continued past the swallow
  assert r.returncode == 42, (
    r.returncode,
    r.stderr,
  )  # ...yet the code leaked out


# --- clean teardown: flux.pool no longer self-TERMs the supervisor -----------
# Regression net for the supervisor-reaper self-kill. `flux.pool` used to `touch` a
# per-run marker and register an at-exit `flux.pool.reap` that ran
# `_mk.super.pid.find | xargs kill -TERM` over ALL of the supervisor's children --
# which includes the `mk.super.exit` make that is *running the reap* -- so every
# pooled run self-TERMed ("make[N]: *** [mk.super.exit/0] Terminated" teardown
# noise). `xargs -P` already waits for/reaps its workers, and any grandchild a
# worker orphans reparents to init (not the supervisor), so the reaper caught
# nothing real and only self-harmed. It (and the marker file) were removed.

POOLBODY = (
  "w/%:; @echo W:$*\n"
  "run:; $(call flux.pool,3,w/a,w/b,w/c,w/d)\n"
  "cleanup:; @echo AT-EXIT-CLEANUP-RAN\n"
  "__main__: run\n"
)


def test_flux_pool_clean_teardown_no_self_term(tmp_path):
  # A pooled run exits 0, runs every worker, and leaves NO "Terminated" teardown
  # noise (the reaper used to self-TERM the mk.super.exit make on every pooled run).
  r = _interpret(tmp_path, POOLBODY, "run")
  assert r.ok, r.stderr
  ran = sorted(w for w in ("W:a", "W:b", "W:c", "W:d") if w in r.stdout)
  assert ran == ["W:a", "W:b", "W:c", "W:d"], r.stdout  # all workers ran
  assert "Terminated" not in (r.stdout + r.stderr), (r.stdout, r.stderr)


def test_flux_pool_leaves_no_marker_file(tmp_path):
  # The reaper's per-run marker (.tmp.cmk.pool.*) is gone -- nothing left behind.
  r = _interpret(tmp_path, POOLBODY, "run")
  assert r.ok, r.stderr
  assert not list(tmp_path.glob(".tmp.cmk.pool.*")), (
    "stale pool marker left behind"
  )


# --- teardown is logged + confirmed clean ------------------------------------
# `mk.super.exit` now emits a visible "teardown clean" confirmation once its
# at-exit handlers have run, so a teardown (normal OR after an interrupt) is
# clearly reported instead of silent. With NO handlers it stays quiet (trace-only),
# to keep simple runs uncluttered.


def test_at_exit_teardown_logged_clean(tmp_path):
  # A CMK_POST handler runs AND the supervisor prints the clean-teardown line.
  r = _interpret(tmp_path, POOLBODY, "run", env={"CMK_POST": "cleanup"})
  assert r.ok, r.stderr
  out = r.stdout + r.stderr
  assert "AT-EXIT-CLEANUP-RAN" in out, out  # handler ran
  assert "teardown clean" in out, out  # ...and was confirmed clean


def test_no_handlers_teardown_stays_quiet(tmp_path):
  # Symmetric: with no at-exit handlers, the visible teardown line is suppressed
  # (the confirmation is opt-in via CMK_POST -- simple runs stay quiet).
  r = _interpret(tmp_path, "__main__:; @echo D\n")
  assert r.ok, r.stderr
  assert "teardown clean" not in (r.stdout + r.stderr), (r.stdout, r.stderr)


# --- user interrupt (Ctrl-C == SIGINT to the whole process group) ------------
# A terminal Ctrl-C signals the WHOLE foreground process group, not just the top
# PID. `_interp_interrupt` reproduces that via `os.killpg` on the child session
# (start_new_session=True makes the child its own group leader). Contract: the run
# stops PROMPTLY with the conventional 130 (128+SIGINT) exit code -- not a hang, and
# not the SIGPIPE crash (141) that used to happen when the supervisor's stderr
# filter pipe broke mid-teardown (fixed by `trap '' PIPE` in the wrapper).

SLEEPBODY = (
  "work:; @echo WORKING; sleep 30\n"
  "cleanup:; @echo AT-EXIT-CLEANUP-RAN\n"
  "__main__: work\n"
)


def _interp_interrupt(
  tmp_path, body, *targets, env=None, settle=2.0, timeout=20
):
  """Run `body` through the interpreter, then group-SIGINT it (like Ctrl-C) once
  it is running, and collect the result (stderr folded into stdout)."""
  prog = tmp_path / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  (tmp_path / "prog.mk").write_text(body)
  merged = {**os.environ, **INTERP_ENV, **(env or {})}
  proc = subprocess.Popen(
    ["./compose.mk", "mk.interpret", "prog.mk", *targets],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    cwd=str(tmp_path),
    env=merged,
    start_new_session=True,
  )
  time.sleep(settle)
  os.killpg(
    os.getpgid(proc.pid), signal.SIGINT
  )  # whole group == terminal Ctrl-C
  try:
    out, _ = proc.communicate(timeout=timeout)
  except subprocess.TimeoutExpired:
    proc.kill()
    proc.communicate()
    raise AssertionError("program did not stop after SIGINT (hung)")
  return Result(out, "", proc.returncode)


def test_sigint_exits_130_promptly(tmp_path):
  # Terminal Ctrl-C on a long-running program: it starts, then stops promptly with
  # the conventional interrupted-exit code 130 -- NOT 141 (the old SIGPIPE crash)
  # and NOT 0 (a swallowed interrupt). Promptness is enforced by the helper timeout.
  t0 = time.time()
  r = _interp_interrupt(tmp_path, SLEEPBODY, env={"CMK_POST": "cleanup"})
  assert "WORKING" in r.stdout, (
    r.stdout
  )  # it actually started before the signal
  assert r.returncode == 130, (
    r.returncode,
    r.stdout,
  )  # clean interrupted code
  assert time.time() - t0 < 15, "did not stop promptly after SIGINT"


# --- root traceback handler (core-owned): a DIRECT bad goal types the same fault as `cmk run` ----
# `compose.mk <missing>` is a bare make goal (not an interpreted program), so it never reaches
# mk.validate.  The supervisor's trampoline loop instead re-runs a failed job's goals under
# `make -n`, classifies via the same diagnoser, and presents the typed fault -- compliant with the
# `fault.*` module without depending on it.  Only under the supervisor (BASE_ENV pins it off).

def _run_direct(tmp_path, *goals, env=None, timeout=60):
  """Run `./compose.mk <goals>` directly (a bare goal, NOT `mk.interpret`), supervisor ON."""
  prog = tmp_path / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  merged = {**os.environ, **INTERP_ENV, **(env or {})}
  proc = subprocess.Popen(
    ["./compose.mk", *goals],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, cwd=str(tmp_path), env=merged, start_new_session=True,
  )
  out, err = proc.communicate(input="", timeout=timeout)
  return Result(out, err, proc.returncode)


def test_root_traceback_handler_types_a_bad_goal(tmp_path):
  # The root handler turns make's raw `No rule to make target` into the themed `RuleMissing:`
  # fault (the same the interpret path gets via mk.validate), for a DIRECT bare goal.
  r = _run_direct(tmp_path, "does-not-exist")
  assert r.returncode != 0
  assert "RuleMissing:" in r.stderr, r.stderr
  assert "No rule to make target 'does-not-exist'" in r.stderr  # raw traceback preserved


def test_root_traceback_handler_quiet_on_success(tmp_path):
  # A valid goal never triggers the handler (no fault header, no spurious ERR block).
  r = _run_direct(tmp_path, "flux.ok")
  assert r.ok, r.stderr
  assert "RuleMissing:" not in r.stderr and "// ERR:" not in r.stderr


# --- router-first: intentional unwinds are control flow, not faults --------------------------
# The trampoline classifies an intentional supervisor unwind (VM transfer / backtrack / a
# saved-exit-code interrupt) BEFORE `mk.super.fault` gets a move.  So the diagnostic handler only
# ever sees a genuinely-unrouted failure -- never a consumed subcommand tail, an interpreted-
# program continuation, or a clean exit.  These pin that ordering (see `_mk.super.tramp`).


def _run_prog(tmp_path, body, *targets, stdin_src="", timeout=60):
  """Run a CMK program via `cmk run` (supervisor ON); capture stdout+stderr separately."""
  prog = tmp_path / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  (tmp_path / "p.cmk").write_text(body)
  merged = {**os.environ, **INTERP_ENV}
  proc = subprocess.Popen(
    ["./compose.mk", "cmk", "run", "p.cmk", *targets],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, cwd=str(tmp_path), env=merged, start_new_session=True,
  )
  out, err = proc.communicate(input=stdin_src, timeout=timeout)
  return Result(out, err, proc.returncode)


def test_fault_silent_on_runtime_failure(tmp_path):
  # A recipe that fails at RUNTIME (not a missing rule / syntax error) is a real failure the
  # diagnoser can't classify -- so the handler stays silent (no spurious `RuleMissing:`), while
  # the program's own error still surfaces.
  r = _run_prog(tmp_path, "__main__:; @echo STARTED; false\n")
  assert r.returncode != 0
  assert "STARTED" in (r.stdout + r.stderr)
  assert "RuleMissing:" not in r.stderr, r.stderr


def test_fault_diagnoses_bad_target_in_program(tmp_path):
  # A genuinely missing target DOES classify (correct context via the nested supervisor) --
  # the fallthrough still works.
  r = _run_prog(tmp_path, "__main__:; @echo ok\n", "no-such-target")
  assert r.returncode != 0
  assert "No rule to make target 'no-such-target'" in r.stderr, r.stderr


def test_consumed_subcommand_tail_is_not_a_fault(tmp_path):
  # `cmk compile` with source on stdin: the supervisor consumes the `compile` verb via the
  # dispatch tail; it must NOT reach the root handler as a spurious `No rule to make target
  # 'compile'`.  Router (dispatch) runs before error-handling.
  prog = tmp_path / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  merged = {**os.environ, **INTERP_ENV, "CMK_DISABLE_HOOKS": "1"}
  proc = subprocess.Popen(
    ["./compose.mk", "cmk", "compile"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True, cwd=str(tmp_path), env=merged, start_new_session=True,
  )
  out, err = proc.communicate(input="__main__:\n\techo hi\n", timeout=60)
  assert "No rule to make target 'compile'" not in err, err
  assert "RuleMissing:" not in err, err
  assert out.lstrip().startswith("#!/usr/bin/env bash"), out[:80]
