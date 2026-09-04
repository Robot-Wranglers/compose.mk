"""Tests for the steerable __vm__ REPL demo (demos/cmk/vm-steer.cmk).

`vm-steer.cmk` is both a DASHBOARD and a DRIVER'S SEAT for the __vm__ machine.  The `print` region
runs a PAUSED machine (vm-steer.machine) that BLOCKS on a steer command; the `eval` region posts a
typed goal to the race-free `__vm__.steer.wait`/`__vm__.steer.post` command channel, and the machine
wakes, `vm.goto`s to it, runs it, and re-blocks.  The mode-line defaults to the core
`tux.repl.modeline`, which now renders the live self-model via `__vm__.snapshot`.

The full TUI needs a tty + the docker-built wrapper, so it is verified manually; here we cover the
HEADLESS contract: mode degradation, the eval->command-channel post, and the end-to-end steer of a
live blocked machine (the headline feature).  Output is captured as BYTES (multibyte glyphs).
"""

import os
import signal
import subprocess
import time
from pathlib import Path

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.external_module, pytest.mark.covers_demo("vm-steer.cmk")]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "vm-steer.cmk"
CMDFILE = REPO / ".tmp.cmk.vm.steer.cmd"


def _dec(b):
  return (
    b.decode("utf-8", "replace")
    if isinstance(b, (bytes, bytearray))
    else (b or "")
  )


def _run_headless(*args, **kw):
  if "input" in kw and isinstance(kw["input"], str):
    kw["input"] = kw["input"].encode()
  if "input" not in kw:
    kw.setdefault("stdin", subprocess.DEVNULL)
  return subprocess.run(
    [str(DEMO), *args],
    cwd=str(REPO),
    capture_output=True,
    start_new_session=True,
    timeout=kw.pop("timeout", 60),
    **kw,
  )


def test_vm_steer_mode_batches_headless():
  # No args -> the `repl` object pragma makes the 3-region harness the default; no tty -> BATCH mode.
  r = _run_headless()
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "entering REPL execution mode" in out, out
  assert "eval=vm-steer.eval" in out and "print=vm-steer.print" in out, out
  assert "streaming stdin into eval" in out, (
    out
  )  # headless BATCH (empty stdin -> no-op)


def test_vm_steer_eval_posts_to_command_channel():
  # The eval sink takes the last word of a typed line as the goal and posts it for the machine.
  CMDFILE.unlink(missing_ok=True)
  try:
    r = _run_headless("vm-steer.eval", input="goto vm-steer.alt\n")
    out = _dec(r.stdout) + _dec(r.stderr)
    assert r.returncode == 0, out
    assert CMDFILE.exists(), out
    assert CMDFILE.read_text().strip() == "vm-steer.alt"
  finally:
    CMDFILE.unlink(missing_ok=True)


def test_vm_steer_drives_a_blocked_machine(tmp_path):
  # The headline: a LIVE, blocked machine is steered from a separate writer.  Background the machine,
  # wait until it is idle (compiled + first tick), post a goal to the command channel, and assert the
  # machine wakes and runs it -- proving interactive steering of a running __vm__ machine.
  log = tmp_path / "machine.log"
  CMDFILE.unlink(missing_ok=True)
  env = {**os.environ, "VM_STEER_MAX": "90", "VM_STEER_WAIT": "1"}
  # stdbuf -> line-buffered, so the background machine's state is observable in the log file.
  proc = subprocess.Popen(
    ["stdbuf", "-oL", "-eL", str(DEMO), "vm-steer.machine"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    stdout=open(log, "wb"),
    stderr=subprocess.STDOUT,
    start_new_session=True,
    env=env,
  )
  try:
    deadline = time.time() + 50
    while time.time() < deadline and "idle tick" not in log.read_text(
      errors="replace"
    ):
      time.sleep(1)
    assert "idle tick" in log.read_text(errors="replace"), (
      "machine never reached idle"
    )
    CMDFILE.write_text("vm-steer.alt\n")  # steer it from a separate writer
    deadline = time.time() + 15
    steered = False
    while time.time() < deadline:
      if "ALT goal reached" in log.read_text(errors="replace"):
        steered = True
        break
      time.sleep(1)
    assert steered, log.read_text(errors="replace")
  finally:
    try:
      os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except Exception:
      pass
    try:
      proc.wait(timeout=10)
    except Exception:
      proc.kill()
    CMDFILE.unlink(missing_ok=True)
