"""tux.repl.debugger.cmk: the VM debugger front-end promoted out of demos/cmk/debugger-example.cmk.

This is the COMPOSITION layer where virtual-machine.cmk (the `__vm__.frames` self-model) meets
tux.repl.cmk (the generic TUI metadata schema) -- neither sibling depends on the other; the coupling
lives only here.  These smoke tests guard the promotion (nothing else covers it):

  (a) the plugin transpiles and exposes its public surface (feed target + overridable view.jq filter);
  (b) the demo still transpiles, rewires its read channel to the promoted feed, keeps vm_trace injecting
      frame.enter into the debuggee recipes, and does NOT inject into the feed (it is the observer); and
  (c) the feed actually resolves at runtime (via the transitive plugin import) and emits one line of
      VALID metadata JSON matching the tux.repl schema.

No docker: (a)/(b) are pure `mk.compile`, (c) runs the feed target headless (no TUI launch).
"""

import json
import os
import re
import signal
import subprocess
import time
from pathlib import Path

import pytest

pytestmark = [pytest.mark.external_plugin, pytest.mark.covers_demo("debugger-example.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
PLUGIN = REPO / ".cmk" / "tux.repl.debugger.cmk"
DEMO = REPO / "demos" / "cmk" / "debugger-example.cmk"

_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _compile(src_path):
  # transpile a .cmk through the real compiler; returns (rc, compiled_stdout).
  r = subprocess.run(
    [str(COMPOSE), "mk.compile"],
    cwd=str(REPO),
    input=src_path.read_text(),
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return r.returncode, r.stdout, _ANSI.sub("", r.stderr)


def _first_json_line(target, timeout=20):
  # the feed loops forever -- grab its first emitted JSON line, then hard-kill the process group.
  proc = subprocess.Popen(
    [str(COMPOSE), "cmk", "run", str(DEMO), target],
    cwd=str(REPO),
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    start_new_session=True,
  )
  line = None
  deadline = time.time() + timeout
  try:
    while time.time() < deadline:
      raw = proc.stdout.readline()
      if not raw:
        break
      raw = raw.strip()
      if raw.startswith("{"):
        line = raw
        break
  finally:
    try:
      os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except ProcessLookupError:
      pass
    proc.wait()
  return line


def test_plugin_transpiles_and_exposes_surface():
  rc, out, err = _compile(PLUGIN)
  assert rc == 0, err
  # the feeder target and the overridable jq view filter (the plugin's whole public surface)
  assert re.search(r"(?m)^tux\.repl\.debugger\.feed:", out), out
  assert re.search(r"(?m)^tux\.repl\.debugger\.view\.jq=", out), out


def test_view_filter_collapses_to_one_line():
  # the \-continuation pretty-print must fold back into a SINGLE jq value (one filter, one command).
  _, out, _ = _compile(PLUGIN)
  assert len(re.findall(r"(?m)^tux\.repl\.debugger\.view\.jq=", out)) == 1, out


def test_demo_rewires_read_to_promoted_feed():
  rc, out, err = _compile(DEMO)
  assert rc == 0, err
  # the pragma now points the read region at the promoted feed (not the old inline frame.meta)
  assert '"read":"tux.repl.debugger.feed"' in out, out
  assert "frame.meta" not in out, (
    "demo still carries the un-promoted machinery"
  )


def test_vm_trace_injects_debuggee_but_not_the_observer():
  _, out, _ = _compile(DEMO)
  # a debuggee recipe gets frame.enter injected as its first line ...
  demo_body = re.search(r"(?m)^demo\.build:\n(.*(?:\n\t.*)*)", out)
  assert demo_body and (
    "frame.enter" in demo_body.group(1) or "vmgoal" in demo_body.group(1)
  ), out
  # ... but the feed (a `tux.` observer) is exempt via CMK_VM_TRACE_SKIP.
  feed_body = re.search(
    r"(?m)^tux\.repl\.debugger\.feed:\n(.*(?:\n\t.*)*)", out
  )
  if feed_body:
    assert "vmgoal" not in feed_body.group(
      1
    ) and "frame.enter" not in feed_body.group(1), out


def test_feed_emits_valid_metadata_json():
  line = _first_json_line("tux.repl.debugger.feed")
  assert line, "feed produced no JSON line"
  d = json.loads(line)  # raises if the feed emitted malformed JSON
  # the tux.repl unified-metadata contract this view drives
  assert "mode_lhs" in d and "mode_rhs" in d, d
  assert d.get("mm_config") == {
    "top": "buffer",
    "middle": "tree",
    "bottom": "mode",
  }, d
  assert d.get("mm_tree", {}).get("label") == "vm", d
