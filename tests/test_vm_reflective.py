"""Tests for the reflective __vm__ environment (`vm.reflect`) and context receive
(`vm.ctx.receive`) -- now that control_stack + __vm__ live in the `.cmk/virtual-machine.cmk` plugin.

A capture POLICY (allowlist `prefix=` or subtraction `exclude=`) makes E reflect the live shell
env, so a coroutine uses plain `export <var>` instead of `__vm__.setenv` and reads it first-class
instead of `__vm__.getenv`.  The policy is brought in by an EXPLICIT `$(call
vm.reflect, ..)` line in the coroutine demo `demos/cmk/vm-coroutines.cmk` (which
imports virtual-machine.cmk then declares it; other demos import it from there) --
the old `# cmk_pragma ::: {virtual_machine: ..} :::` compiler injection was REMOVED in favor of
this explicit form.  Context receive (`vm.ctx.receive`) re-hydrates E at a goal's entry -- the
`vm_hydrate` pragma auto-injects it (as the eval-wrapping `@vm.ctx.hydrate` decorator), or
`@vm.ctx.hydrate` places it by hand.  Dormant (zero cost) unless declared -- the fast-path invariant is covered by
tests/test_vm.py (whose demos never declare).
"""

import json
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module, pytest.mark.covers_demo("vm-coroutines.cmk")]

REPO = Path(__file__).resolve().parent.parent


def _run(demo):
  return subprocess.run(
    [str(REPO / "demos" / demo)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=60,
  )


def test_reflective_exclude_via_explicit_declare_and_pragma():
  # exclude (.cmk): the EXPLICIT vm.reflect call brings the policy into scope and the
  # `vm_hydrate` pragma auto-receives at each entry -- plain `export phase` (no prefix); E stays clean.
  r = _run("cmk/vm-coroutines.cmk")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "done phase=2" in out, out  # cmk.log output of the final phase
  m = re.search(r"persisted E = (\{.*\})", out)
  assert m, out
  e = json.loads(m.group(1))
  # E reflects ONLY the coroutine's own export (the exclude policy drops the make/cmk machinery,
  # including the kwargs_/CONTROL_STACK vars the plugin imports export at parse).
  assert e == {"phase": "2"}, e


def test_virtual_machine_pragma_no_longer_injects():
  # The `virtual_machine` compiler pragma was REMOVED: vm.reflect now lives in the
  # __vm__ plugin and is called explicitly.  A source carrying the old pragma must NOT get a
  # declaration injected at compile time.
  src = b'# cmk_pragma ::: { "virtual_machine": "exclude=MAKE" } :::\nprobe:; @true\n'
  r = subprocess.run(
    [str(REPO / "compose.mk"), "mk.compile"],
    cwd=str(REPO),
    input=src,
    capture_output=True,
    timeout=60,
  )
  out = r.stdout.decode("utf-8", "replace")
  assert "vm.reflect" not in out, out


def test_demo_uses_explicit_declaration():
  # The reflective coroutine lives in demos/cmk/vm-coroutines.cmk (no demos in libraries): it imports
  # the __vm__ plugin, OPTS IN to the reflective env via vm.reflect, and requests the
  # `compiler_post: [vm_hydrate]` stage so the compiler auto-receives context at each recipe entry -- so it
  # never calls setenv/getenv and needs no hand-placed decorator (the whole point).
  demo = (REPO / "demos" / "cmk" / "vm-coroutines.cmk").read_text()
  assert (
    "import virtual-machine.cmk" in demo
  )  # imports the extracted __vm__ plugin
  assert (
    "$(call vm.reflect," in demo
  )  # EXPLICIT reflective-env declaration
  assert (
    '"compiler_post"' in demo and '"vm_hydrate"' in demo
  )  # the compiler_post stage that drives auto-receive
  assert (
    "@vm.ctx.receive" not in demo
  )  # no hand-placed decorator (auto-injected now)
  assert "$(call __vm__.setenv" not in demo
  assert "$(call __vm__.getenv" not in demo
  # ...and other demos consume it by importing it FROM demos/ (overlay), not from a library.
  overlay = (REPO / "demos" / "cmk" / "overlay.cmk").read_text()
  assert "import demos/cmk/vm-coroutines.cmk" in overlay
