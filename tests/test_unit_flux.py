"""Unit tests for the flux.* control-flow / algebra targets.

flux.* is mostly exit-code composition: the bare primitives log to stderr,
so their stdout is empty and behavior is asserted via the return code. A
few targets (flux.echo, flux.map, flux.each, flux.if.then) are identity/map
helpers with deterministic stdout.

As in test_unit_streams, expected values encode *intended* behavior and
known defects are pinned with xfail. Note: a failing target surfaces as
make's exit code 2 (not 1), so failure is asserted with ``not r.ok``.
"""

import json
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


# (target, stdin, expected_stdout) - identity/map helpers with clean stdout.
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
  # apply: target + optional arg.
  ("flux.apply/flux.echo,THUNK", "", "THUNK\n"),
  # do.when / do.unless: run 1st target iff 2nd succeeds / fails.
  ("flux.do.when/flux.echo/THEN,flux.ok", "", "THEN\n"),
  ("flux.do.unless/flux.echo/U,flux.fail", "", "U\n"),
  # pipeline: `make t1 | make t2 | ...` (default quiet=1 prints last stage).
  ("flux.pipeline/flux.echo/solo", "", "solo\n"),
  ("flux.pipeline/flux.echo/hello,stream.indent", "", "  hello\n"),
  ("flux.pipeline/flux.echo/hi,stream.indent,stream.indent", "", "    hi\n"),
  ("flux.pipeline.quiet/flux.echo/hello,stream.indent", "", "  hello\n"),
  # flux.column: same, but colon-delimited stages.
  ("flux.column/flux.echo/hi:stream.indent", "", "  hi\n"),
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
  "flux.apply/flux.ok",
  "flux.wrap/flux.ok:flux.ok",
  "flux.loop/2/flux.noop",
  "flux.loop.until/flux.ok",
  "flux.timer/flux.ok",
  "flux.timeout/3/flux.ok",
  "flux.all/flux.ok,flux.ok",
  "flux.any/flux.fail,flux.ok",
  "flux.finally/flux.ok",
  "flux.always/flux.ok",
  "flux.parallel/flux.ok,flux.ok",
  "flux.stream.obliviate/flux.ok",
  "flux.indent/flux.ok",
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
  "flux.NIY",
  "flux.wrap/flux.ok:flux.fail",
  "flux.all/flux.ok,flux.fail",
  "flux.parallel/flux.ok,flux.fail",
]


@pytest.mark.parametrize("target", FAIL_CASES)
def test_flux_fails(cmk, target):
  r = cmk(target)
  assert not r.ok, f"{target} should exit non-zero but got 0"


def test_flux_timeout_sh_runs_command(cmk):
  # The shell-command variant (env cmd=, timeout=) - exercises the fix that
  # made it run `bash -c "$cmd"` and honor the env timeout.
  r = cmk("flux.timeout.sh", env={"cmd": "echo TOUT", "timeout": "3"})
  assert r.ok, r.stderr
  assert "TOUT" in r.stdout


def test_flux_split_fans_out(cmk):
  # flux.split (= flux.pipe.fork) sends stdin to EACH named target. (tee also
  # passes stdin through, so the marker appears once more than #targets.)
  r = cmk("flux.split/stream.echo,stream.echo", stdin="FORKME\n")
  assert r.ok, r.stderr
  assert r.stdout.count("FORKME") >= 2  # both targets received the input


def test_flux_sh_tee(cmk):
  # The shell-command primitive behind flux.split.
  r = cmk("flux.sh.tee", stdin="TEEME\n", env={"cmds": "cat,cat"})
  assert r.ok, r.stderr
  assert r.stdout.count("TEEME") >= 2


# --- flux.stage.* : file-backed JSON stack, isolated in the fixture cwd ------
# (cwd defaults to tmp_path, so `.flux.stage.*` files never touch the repo.)

# enter/wrap draw a banner via io.draw.banner (gum -> docker); override it with
# a silent target so these stay pure unit tests.
_QUIET_BANNER = {"banner_target": "flux.noop"}


def test_flux_stage_file_path(cmk):
  r = cmk("flux.stage.file/foo")
  assert r.ok, r.stderr
  assert r.stdout.strip() == ".flux.stage.foo"


def test_flux_stage_current_from_env(cmk):
  r = cmk("flux.stage", env={"FLUX_STAGE": "xyz"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "xyz"


def test_flux_stage_push_and_stack(cmk):
  cmk("flux.stage.push/s", stdin='{"k":1}')
  cmk("flux.stage.push/s", stdin='{"k":2}')
  r = cmk("flux.stage.stack/s")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == [{"k": 1}, {"k": 2}]


def test_flux_stage_pop(cmk):
  cmk("flux.stage.push/s", stdin='{"k":1}')
  r = cmk("flux.stage.pop/s")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == {"k": 1}


def test_flux_stage_enter_then_exit(cmk, tmp_path):
  enter = cmk("flux.stage.enter/s1", env=_QUIET_BANNER)
  assert enter.ok, enter.stderr
  stack = cmk("flux.stage.stack/s1")
  assert any("stage.entered" in e for e in json.loads(stack.stdout))
  exit_ = cmk("flux.stage.exit/s1")
  assert exit_.ok, exit_.stderr
  assert not (tmp_path / ".flux.stage.s1").exists()


def test_flux_stage_clean(cmk, tmp_path):
  cmk("flux.stage.enter/s2", env=_QUIET_BANNER)
  assert (tmp_path / ".flux.stage.s2").exists()
  cmk("flux.stage.clean/s2")
  assert not (tmp_path / ".flux.stage.s2").exists()


def test_flux_stage_wrap(cmk):
  r = cmk("flux.stage.wrap/MAIN/flux.ok", env=_QUIET_BANNER)
  assert r.ok, r.stderr


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


# --- flux.fold / flux.reduce (left-fold + reduce over stdin lines) ----------
# The accumulator threads through the reducer target's STDIN; the current line
# is passed as the `val` env-var; the reducer prints the new accumulator. So a
# stdlib stream reducer (stream.json.array.append reads stdin + `val`) drops in
# directly, while scalar reducers read the accumulator via `${stream.stdin}`.


def _reducers(tmp_path):
  """Wrapper makefile defining scalar fold/reduce reducers."""
  mk = tmp_path / "reducers.mk"
  mk.write_text(
    f"include {COMPOSE_MK}\n"
    "add:; @echo $$(( `${stream.stdin}` + $${val} ))\n"
    'max:; @a=`${stream.stdin}`; [ "$${a}" -gt "$${val}" ]'
    ' && echo "$${a}" || echo "$${val}"\n'
  )
  return mk


def test_flux_fold_into_json_array(cmk):
  # A stdlib stream reducer drops in as the fold reducer with no adapter.
  r = cmk("flux.fold/stream.json.array.append,[]", stdin="a\nb\nc\n")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == ["a", "b", "c"]


def test_flux_fold_scalar_with_init(cmk, tmp_path):
  r = cmk(
    "flux.fold/add,0", stdin="1\n2\n3\n4\n", makefile=_reducers(tmp_path)
  )
  assert r.ok, r.stderr
  assert r.stdout.strip() == "10"


def test_flux_fold_empty_returns_init(cmk):
  # No input -> the accumulator is just the (init) seed.
  r = cmk("flux.fold/stream.json.array.append,[]", stdin="")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == []


def test_flux_reduce_seeded_by_head(cmk, tmp_path):
  # reduce = fold seeded by the first line (no init): max of the list.
  r = cmk(
    "flux.reduce/max", stdin="3\n1\n4\n1\n5\n", makefile=_reducers(tmp_path)
  )
  assert r.ok, r.stderr
  assert r.stdout.strip() == "5"


def test_flux_reduce_single_line_is_identity(cmk, tmp_path):
  # A single element folds to itself (the reducer never runs).
  r = cmk("flux.reduce/max", stdin="42\n", makefile=_reducers(tmp_path))
  assert r.ok, r.stderr
  assert r.stdout.strip() == "42"


def test_flux_reduce_empty_input_fails(cmk, tmp_path):
  r = cmk("flux.reduce/max", stdin="", makefile=_reducers(tmp_path))
  assert not r.ok
