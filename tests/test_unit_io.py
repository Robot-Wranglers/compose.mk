"""Tests for the io.* targets.

Most io.* targets are pure (stdin/args -> stdout, or small filesystem effects)
and unit-testable. `io.env*` is made deterministic by injecting known env vars
(a "mock" environment). Tool-backed targets that compose.mk normally provides
via a container (e.g. io.figlet) are marked `needs_docker` so they auto-skip
without that heavier environment.

Several io.* targets emit on stderr (banners, figlet), so those assert exit
status rather than stdout. As elsewhere, known bugs are pinned with xfail.
"""

import json
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"

# --- pure: stdout ----------------------------------------------------------


@pytest.mark.unit
def test_io_echo_passthrough(cmk):
  r = cmk("io.echo", stdin="hello")
  assert r.ok, r.stderr
  assert r.stdout == "hello"


@pytest.mark.unit
def test_io_env_filters_by_prefix(cmk):
  # Mock the environment: only FOO_BAR should match the FOO prefix.
  r = cmk("io.env/FOO", env={"FOO_BAR": "baz"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "FOO_BAR=baz"


@pytest.mark.unit
def test_io_env_excludes_nonmatching_prefix(cmk):
  r = cmk("io.env/NOPE", env={"FOO_BAR": "baz"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == ""


@pytest.mark.unit
def test_io_env_json(cmk):
  r = cmk("io.env.json/FOO", env={"FOO_BAR": "baz"})
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == {"FOO_BAR": "baz"}


@pytest.mark.unit
def test_io_awk(cmk, tmp_path):
  # io.awk runs a named define-block as an awk script over stdin.
  mk = tmp_path / "wrap.mk"
  mk.write_text(
    f"include {COMPOSE_MK}\ndefine upcase\n{{print toupper($0)}}\nendef\n"
  )
  r = cmk("io.awk/upcase", stdin="hi there", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "HI THERE"


# --- pure: exit-code semantics ---------------------------------------------


@pytest.mark.unit
def test_io_force_runs_target(cmk):
  r = cmk("io.force/flux.ok")
  assert r.ok, r.stderr


@pytest.mark.unit
def test_io_force_propagates_failure(cmk):
  r = cmk("io.force/flux.fail")
  assert not r.ok


@pytest.mark.unit
def test_io_time_wait_zero(cmk):
  r = cmk("io.time.wait/0")
  assert r.ok, r.stderr


@pytest.mark.unit
def test_io_quiet_stderr(cmk):
  assert cmk("io.quiet.stderr/flux.ok").ok
  assert not cmk("io.quiet.stderr/flux.fail").ok


@pytest.mark.unit
def test_io_env_log(cmk):
  r = cmk("io.env.log")
  assert r.ok, r.stderr


@pytest.mark.unit
def test_io_print_banner_exits_clean(cmk):
  # Output is on stderr; width is pinned so it doesn't depend on the terminal.
  r = cmk("io.print.banner/HELLO", env={"width": "40"})
  assert r.ok, r.stderr


# --- pure: filesystem (isolated in tmp_path via the cmk fixture's cwd) ------


@pytest.mark.unit
def test_io_mkdir(cmk, tmp_path):
  r = cmk("io.mkdir/sub/dir")
  assert r.ok, r.stderr
  assert (tmp_path / "sub" / "dir").is_dir()


@pytest.mark.unit
def test_io_stack_push_and_read(cmk):
  cmk("io.stack.push/st", stdin='{"a":1}')
  cmk("io.stack.push/st", stdin='{"b":2}')
  r = cmk("io.stack/st")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == [{"a": 1}, {"b": 2}]


@pytest.mark.unit
def test_io_stack_pop_is_lifo(cmk):
  # io.stack.push appends (top == last); io.stack.pop returns and removes the
  # last element (proper LIFO).
  cmk("io.stack.push/st", stdin='{"a":1}')
  cmk("io.stack.push/st", stdin='{"b":2}')
  popped = cmk("io.stack.pop/st")
  assert json.loads(popped.stdout) == {"b": 2}  # returned value
  remaining = cmk("io.stack/st")
  assert json.loads(remaining.stdout) == [{"a": 1}]  # the top was removed


@pytest.mark.unit
def test_io_stack_discard_removes_without_returning(cmk):
  # io.stack.discard is io.stack.pop minus the return: it trims the top off the
  # stack and emits nothing.
  cmk("io.stack.push/st", stdin='{"a":1}')
  cmk("io.stack.push/st", stdin='{"b":2}')
  discarded = cmk("io.stack.discard/st")
  assert discarded.ok, discarded.stderr
  assert discarded.stdout.strip() == ""  # nothing returned (unlike pop)
  remaining = cmk("io.stack/st")
  assert json.loads(remaining.stdout) == [{"a": 1}]  # the top was removed


@pytest.mark.unit
def test_io_stack_macro_empty_arg_defaults_to_default_stack(cmk, tmp_path):
  # The CMK `cmk.io.stack.*()` sugar lowers to a trailing-comma `$(call
  # io.stack.X,)`, i.e. ${1} is defined-but-EMPTY. The resolver must fall back to
  # ${CMK_IO_STACK} (not an empty filename). Exercise reset/push/pop.word in that
  # empty-arg form and confirm they operate on the default stack.
  mk = tmp_path / "w.mk"
  mk.write_text(
    f"include {COMPOSE_MK}\n"
    "probe:\n"
    "\t@$(call io.stack.reset,)\n"
    "\t@printf '\"x\"' | $(call io.stack.push,)\n"
    "\t@$(call io.stack.pop_word,)\n"
  )
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "x"


# Docker-gated io.* targets (e.g. io.figlet) live in test_docker_io.py.
