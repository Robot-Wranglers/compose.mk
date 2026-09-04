"""A subcommand `__main__` is implicit: nobody types the entry target's name.

`cmk run <prog> <verb>` hands its trailing words to the program as make goals. When
the program's `__main__` is a `cli.subcommands` entry, a leading word that names no
target routes to that entry as a subcommand instead of failing as an unknown goal,
and the rendered usage line drops the entry name. A program whose `__main__` is an
ordinary recipe is untouched, so a typo'd goal still errors.
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.entrypoint]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

SUBCOMMAND_PROG = (
  "import log\n"
  "\n"
  "__main__:\n"
  "  '''a demo cli'''\n"
  "  cmk.cli.subcommands.enter(namespace=ns subs='hello')\n"
  "\n"
  "ns.hello:\n"
  "  '''say hello'''\n"
  "  cmk.log(hello ran)\n"
)
PLAIN_PROG = (
  "import log\n"
  "\n"
  "__main__:\n"
  "  '''an ordinary entrypoint'''\n"
  "  cmk.log(main ran)\n"
)


def _run(tmp_path, prog, *args):
  f = tmp_path / "prog.cmk"
  f.write_text(prog)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *args],
    cwd=str(tmp_path),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=180,
    env={**os.environ, "NO_COLOR": "1"},
  )
  return r.returncode, r.stdout + r.stderr


def test_implicit_main_dispatches_a_bare_subcommand(tmp_path):
  # `hello` names no target, so it routes to the subcommand entry.
  rc, out = _run(tmp_path, SUBCOMMAND_PROG, "hello")
  assert rc == 0, out
  assert "hello ran" in out, out


def test_implicit_main_leaves_a_real_target_alone(tmp_path):
  # a word that does name a target still runs as an ordinary goal.
  rc, out = _run(tmp_path, SUBCOMMAND_PROG, "ns.hello")
  assert rc == 0, out
  assert "hello ran" in out, out


def test_implicit_main_reports_an_unknown_subcommand(tmp_path):
  rc, out = _run(tmp_path, SUBCOMMAND_PROG, "nosuchverb")
  assert rc != 0, out
  assert "unknown subcommand" in out, out


def test_usage_line_omits_the_implicit_entry(tmp_path):
  # only the spelled invocation is asserted; the log prefix still names the target.
  rc, out = _run(tmp_path, SUBCOMMAND_PROG)
  assert rc == 0, out
  spelled = [
    ln.split("USAGE:", 1)[1] for ln in out.splitlines() if "USAGE:" in ln
  ]
  assert spelled, out
  assert "__main__" not in " ".join(spelled), out
  assert "prog.cmk <subcommand>" in " ".join(spelled), out


def test_plain_main_still_fails_on_an_unknown_goal(tmp_path):
  # no subcommand entry, so the routing must not fire and swallow the typo.
  rc, out = _run(tmp_path, PLAIN_PROG, "nosuchgoal")
  assert rc != 0, out
  assert "main ran" not in out, out
