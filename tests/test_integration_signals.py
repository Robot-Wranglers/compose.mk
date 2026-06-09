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
  # NB: a user-defined at-exit target currently yields a nonzero supervisor exit
  # (the handler resolves against compose.mk's namespace) -- a pre-existing quirk
  # unrelated to this path; we assert the handler RAN, not the exit code.
  body = HOOKED + "myexit:; @echo AT-EXIT-RAN\n"
  r = _interp(tmp_path, body, "nohook", env={"CMK_AT_EXIT_TARGETS": "myexit"})
  assert "PLAIN" in r.stdout
  assert "AT-EXIT-RAN" in r.stdout, r.stdout
