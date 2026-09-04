"""REPL-as-execution-mode: a `repl` manifest pragma makes `cmk run` launch the interactive tux.repl
harness over a program's own targets -- with NO tux.repl import / host_only / declare boilerplate in the
program.  `cmk repl <file>` is the explicit/universal form (force the mode on ANY program).

These cover the HEADLESS contract end-to-end through `cmk run` / `cmk repl`: the pragma is recognized,
the runtime assembles the harness wiring (generic tux.repl.kernel eval for `true`; read/eval/print for the
object form), and with no tty it runs in BATCH (stdin streams into the eval).  The live TUI is verified manually.
The bypass semantics (an explicit target runs instead of opening the REPL) are checked too.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_plugin]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(subcmd, *args, timeout=120):
  r = subprocess.run(
    [str(COMPOSE), "cmk", subcmd, *[str(a) for a in args]],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    start_new_session=True,
    timeout=timeout,
  )
  out = (r.stdout or b"").decode("utf-8", "replace") + (
    r.stderr or b""
  ).decode("utf-8", "replace")
  return r.returncode, re.sub(r"\x1b\[[0-9;]*m", "", out)


def _write(tmp_path, body, name="prog.cmk"):
  f = tmp_path / name
  f.write_text(body)
  f.chmod(0o755)
  return f


def test_repl_true_pragma_is_zero_boilerplate(tmp_path):
  # The plan's minimal case: a `repl: true` header + a bare target, NOTHING else -- no import, no
  # host_only, no declare, no __main__.  `cmk run` enters the mode and wires the generic dispatcher.
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "repl": true } :::\nflux.demo:; @echo hi\n',
  )
  rc, out = _run("run", f)
  assert rc == 0, out
  assert "entering REPL execution mode" in out, out
  assert "eval=tux.repl.kernel" in out, (
    out
  )  # generic target-namespace dispatcher
  assert "streaming stdin into eval" in out, (
    out
  )  # headless BATCH (empty stdin -> no-op)


def test_repl_object_pragma_wires_regions(tmp_path):
  # The object form selects custom read/eval/print regions (the overlay case).  The runtime parses the
  # JSON object (jq) and assembles the harness arg string.
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "repl": { "eval": "my.eval", "read": "my.read", "print": "my.print", "exit_after": 1 } } :::\n'
    "my.eval:; @echo e\n"
    "my.read:; @echo r\n"
    "my.print:; @echo p\n",
  )
  rc, out = _run("run", f)
  assert rc == 0, out
  assert "entering REPL execution mode" in out, out
  for frag in (
    "eval=my.eval",
    "read=my.read",
    "print=my.print",
    "exit_after=1",
  ):
    assert frag in out, (frag, out)


def test_explicit_target_bypasses_the_mode(tmp_path):
  # An explicit target runs (like `python script.py`), NOT the REPL.  Needs a __main__ for the
  # interpret path; the target itself is what we assert ran.
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "repl": true } :::\n'
    "__main__: flux.demo\n"
    "flux.demo:; @echo BYPASS-RAN\n",
  )
  rc, out = _run("run", f, "flux.demo")
  assert rc == 0, out
  assert "BYPASS-RAN" in out, out
  assert "entering REPL execution mode" not in out, out


def test_cmk_repl_no_file_drops_to_core_shell():
  # `cmk repl` with NO filename drops to a simple shell over the CORE namespace (an empty program:
  # no local targets, nothing to exec) -- not an error.
  rc, out = _run("repl")
  assert rc == 0, out
  assert "simple shell over the core namespace" in out, out
  assert "eval=tux.repl.kernel" in out, out
  assert "streaming stdin into eval" in out, (
    out
  )  # headless BATCH (empty stdin -> no-op)
  assert "No rule to make target" not in out, (
    out
  )  # the old bare-`cmk repl` failure


def test_cmk_repl_subcommand_forces_mode_on_any_file(tmp_path):
  # `cmk repl <file>` opens the harness over ANY program -- even one with NO repl pragma -- as the
  # universal interactive shell over its target namespace.
  f = _write(
    tmp_path,
    "hello:; @echo hi\n__main__: hello\n",
  )
  rc, out = _run("repl", f)
  assert rc == 0, out
  assert "eval=tux.repl.kernel" in out, (
    out
  )  # generic dispatcher, no pragma needed
  assert "streaming stdin into eval" in out, (
    out
  )  # headless BATCH (empty stdin -> no-op)


def test_plain_program_without_pragma_runs_normally(tmp_path):
  # Regression: no `repl` pragma -> `cmk run` runs __main__ as before (the mode is opt-in).
  f = _write(
    tmp_path,
    "__main__:; @echo NORMAL-RUN\n",
  )
  rc, out = _run("run", f)
  assert rc == 0, out
  assert "NORMAL-RUN" in out, out
  assert "REPL execution mode" not in out, out
