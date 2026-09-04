"""End-to-end for the `LHS <- Class.new()` instantiation form.

`Class.new()` in capture position mints a FRESH instance under the LHS name: the capture
stage rewrites `alice <- Pet.new()` to `$(call Pet,alice)` (a class is its own positional
ctor, so LHS becomes `self`), the sibling of `<obj>.copy()`.  The compile-level lowering is
pinned in test_receivers_cmk.py::test_new_threads_instance_name; this confirms the minted
instance actually WORKS -- dispatches through its late-bound hook, carries the right
reflection, and stays independent of a sibling instance.

Marked `unit` (fast, no docker).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# Two instances of one class: alice overrides its `.sound`, bob keeps the class default.  The
# `${self}/%` hook echoes the instance name, the stem, and the instance's own `.sound`, so the
# output distinguishes per-instance state and proves dispatch runs through the minted hook.
PROG = (
  "from cmk import class\n"
  "import log\n"
  "class Pet[|\n"
  "  ${self}.sound ?= generic\n"
  "  ${self}/%:; log(${self}/$* says $(${self}.sound))\n"
  "|]\n"
  "alice <- Pet.new()\n"
  "alice.sound := woof\n"
  "bob <- Pet.new()\n"
  "demo:\n"
  "  this.alice/greet\n"
  "  this.bob/greet\n"
  "  log(acls=${alice.__class__} bcls=${bob.__class__})\n"
  "__main__: demo\n"
)


def _run(tmp_path, src, goal=None):
  f = tmp_path / "inst.cmk"
  f.write_text(src)
  argv = [str(COMPOSE), "cmk", "run", str(f)] + ([goal] if goal else [])
  return subprocess.run(
    argv,
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )


def test_new_instance_dispatches_and_reflects(tmp_path):
  r = _run(tmp_path, PROG)
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  # alice dispatches through its own `${self}/%` hook, carrying its OVERRIDDEN state.
  assert "alice/greet says woof" in out, out
  # bob is a distinct instance of the same class: its `.sound` is the untouched class default.
  assert "bob/greet says generic" in out, out
  # both instances carry the correct `.__class__` reflection.
  assert "acls=Pet" in out and "bcls=Pet" in out, out
