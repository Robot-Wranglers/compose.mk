"""Boot-knob pragmas: `bootloaders` / `cmk_post` (the before/after pair) + the `hooks` and
`bootloader_disabled` scalar toggles.

These knobs are read by compose.mk's bash polyglot header BEFORE make exists, so the generic
CMK_PRAGMA_* injection can't reach them.  `cli.cmk.run/%` extracts them from the compiled output and
threads the canonical CMK_DISABLE_HOOKS / CMK_BOOTLOADER* env into the program's re-exec.  Phase 0
also generalized the bootloader so a user bootloader can be an inline named `define` (no external
file).  All of this only applies via `cmk run` (the path that owns the source + the re-exec).
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run_cmk(path, env=None, timeout=90):
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(path)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=timeout,
    env=({**__import__("os").environ, **env} if env else None),
  )
  out = (r.stdout or b"").decode("utf-8", "replace") + (
    r.stderr or b""
  ).decode("utf-8", "replace")
  return r.returncode, re.sub(r"\x1b\[[0-9;]*m", "", out)


def _write(tmp_path, body):
  f = tmp_path / "prog.cmk"
  f.write_text(body)
  f.chmod(0o755)
  return f


def test_bootloaders_inline_define_before_after_lifecycle():
  # The shipped demo exercises every lifecycle surface, before -> main -> after:
  #   bootloaders (bash, sourced in supervisor; registers an EXIT trap),
  #   cmk_pre (a make-target run at boot, declarative), then main, then cmk_post.
  rc, out = _run_cmk(REPO / "demos" / "cmk" / "pragma-boot.cmk")
  assert rc == 0, out
  for marker in (
    "[boot] setup",  # bash bootloader (sh.bootloader.example)
    "[boot] cmk_pre make-target",  # declarative: cmk_pre runs __setup__
    "[main]",
    "[exit] teardown",  # cmk_post (__teardown__)
    "[boot] EXIT trap fired",  # the bash bootloader's EXIT trap, last
  ):
    assert marker in out, (marker, out)
  # Ordering: bash bootloader -> cmk_pre make-target -> main -> cmk_post -> EXIT trap.
  assert (
    out.index("[boot] setup")
    < out.index("[boot] cmk_pre make-target")
    < out.index("[main]")
    < out.index("[exit] teardown")
    < out.index("[boot] EXIT trap fired")
  )


def test_hooks_pragma_disables_hooks(tmp_path):
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "hooks": "off" } :::\n'
    '__main__:; @echo "DH=$$CMK_DISABLE_HOOKS"\n',
  )
  rc, out = _run_cmk(f)
  assert rc == 0, out
  assert "DH=1" in out, out  # program boots with hooks disabled
  assert "pragma hooks=off" in out, out  # loud notice


def test_pragma_survives_blank_line_before_it(tmp_path):
  # Regression guard for the blank-line pragma-header footgun.  The scanner lang.parse.pragma.hint
  # (compose.mk) collects the top comment block and used to exit at the first NON-comment line --
  # and a BLANK line is non-comment -- so a `cmk_pragma` below a blank was silently dropped (it
  # broke demos/cmk/repl.cmk when f568c78 inserted a blank after the shebang).  The scanner now
  # tolerates blank lines (`!/#/ && NF` -- exit only on a non-blank non-comment line), so the pragma
  # is reached in the real-world shape below: shebang, a blank line, THEN the pragma.  The loud
  # `pragma hooks=off` notice fires iff the pragma was extracted (DH can be 1 for other reasons).
  f = _write(
    tmp_path,
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "\n"
    '# cmk_pragma ::: { "hooks": "off" } :::\n'
    "__main__:; @echo MAIN\n",
  )
  rc, out = _run_cmk(f)
  assert rc == 0, out
  assert "pragma hooks=off" in out, out  # pragma reached despite the leading blank line


def test_pragma_below_first_code_line_is_ignored(tmp_path):
  # Boundary companion to the blank-tolerance heal: tolerating blanks must NOT turn the header scan
  # into a runaway.  The header still ends at the first non-blank NON-comment line, so a `cmk_pragma`
  # sitting BELOW a code line is out of the header and never takes -- no notice, hooks stay enabled.
  f = _write(
    tmp_path,
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "__main__:; @echo MAIN\n"
    '# cmk_pragma ::: { "hooks": "off" } :::\n',
  )
  rc, out = _run_cmk(f)
  assert rc == 0, out
  assert "MAIN" in out, out
  assert "pragma hooks=off" not in out, out  # below-code pragma is out of the header, ignored


def test_bootloader_disabled_pragma(tmp_path):
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "bootloader_disabled": "1" } :::\n'
    "__main__:; @echo MAIN\n",
  )
  rc, out = _run_cmk(f)
  assert rc == 0, out
  assert "MAIN" in out
  assert (
    "bootloader disabled" in out
  )  # the header's disabled-boot path was taken


def test_bootloaders_append_with_invoker_env(tmp_path):
  # A FILE bootloader from the invoker env AND an inline-define bootloader from the pragma BOTH run
  # (list append, not override).
  bootfile = tmp_path / "inv.sh"
  bootfile.write_text('echo "INVOKER-BOOT-RAN"\n')
  f = _write(
    tmp_path,
    '# cmk_pragma ::: { "bootloaders": ["boot.x"] } :::\n'
    "define boot.x\n"
    'echo "PRAGMA-BOOT-RAN"\n'
    "endef\n"
    "__main__:; @echo MAIN\n",
  )
  rc, out = _run_cmk(f, env={"CMK_BOOTLOADER": str(bootfile)})
  assert rc == 0, out
  assert "INVOKER-BOOT-RAN" in out, out  # invoker's file bootloader
  assert "PRAGMA-BOOT-RAN" in out, (
    out
  )  # pragma's inline-define bootloader -- both ran
