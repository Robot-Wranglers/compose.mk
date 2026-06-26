"""Tests for the reflective __vm__ environment (`declare.cmk.virtual_machine`) and the
`ᝏ__vm__.env.load` decorator -- now that control_stack + __vm__ live in the `.cmk/virtual-machine.cmk` plugin.

A capture POLICY (allowlist `prefix=` or subtraction `exclude=`) makes E reflect the live shell
env, so a coroutine uses plain `export <var>` instead of `__vm__.setenv` and reads it first-class
instead of `__vm__.getenv`.  The policy is brought in by an EXPLICIT `$(call
declare.cmk.virtual_machine, ..)` line in the shared `.cmk/coroutines.cmk` plugin (which imports
virtual-machine.cmk then declares it; demos/cmk/vm-coroutines.cmk is now a thin consumer of that plugin) --
the old `# cmk_pragma ::: {virtual_machine: ..} :::` compiler injection was REMOVED in favor of
this explicit form.  The `ᝏ__vm__.env.load` decorator prepends the re-hydration
to a goal's recipe.  Dormant (zero cost) unless declared -- the fast-path invariant is covered by
tests/test_vm.py (whose demos never declare).
"""

import json
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

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


def test_reflective_exclude_via_explicit_declare_and_decorator():
  # exclude (.cmk): the EXPLICIT declare.cmk.virtual_machine call brings the policy into scope and
  # the ᝏ__vm__.env.load DECORATOR re-hydrates -- plain `export phase` (no prefix); E stays clean.
  r = _run("cmk/vm-coroutines.cmk")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "done phase=2" in out, out  # cmk.log.target output of the final phase
  m = re.search(r"persisted E = (\{.*\})", out)
  assert m, out
  e = json.loads(m.group(1))
  # E reflects ONLY the coroutine's own export (the exclude policy drops the make/cmk machinery,
  # including the kwargs_/CONTROL_STACK vars the plugin imports export at parse).
  assert e == {"phase": "2"}, e


def test_virtual_machine_pragma_no_longer_injects():
  # The `virtual_machine` compiler pragma was REMOVED: declare.cmk.virtual_machine now lives in the
  # __vm__ plugin and is called explicitly.  A source carrying the old pragma must NOT get a
  # declaration injected at compile time.
  src = b'# cmk_pragma ::: { "virtual_machine": "exclude=MAKE" } :::\nprobe:; @true\n'
  r = subprocess.run(
    [str(REPO / "compose.mk"), "mk.compile"],
    cwd=str(REPO), input=src, capture_output=True, timeout=60,
  )
  out = r.stdout.decode("utf-8", "replace")
  assert "declare.cmk.virtual_machine" not in out, out


def test_demo_uses_explicit_declaration():
  # The reflective coroutine now lives in the shared `.cmk/coroutines.cmk` plugin: IT imports the
  # __vm__ plugin and OPTS IN explicitly (no compiler pragma), and the ᝏ__vm__.env.load decorator
  # re-hydrates E so it never calls setenv/getenv (the whole point).
  plugin = (REPO / ".cmk" / "coroutines.cmk").read_text()
  assert "include.plugins, virtual-machine.cmk" in plugin          # imports the extracted __vm__ plugin
  assert "$(call declare.cmk.virtual_machine," in plugin     # EXPLICIT declaration
  assert "cmk_pragma" not in plugin                          # no compiler pragma
  assert "ᝏ__vm__.env.load" in plugin                        # the decorator
  assert "$(call __vm__.setenv" not in plugin
  assert "$(call __vm__.getenv" not in plugin
  # ...and the demo is now just a thin consumer that imports the shared plugin (no inlined coroutine).
  demo = (REPO / "demos" / "cmk" / "vm-coroutines.cmk").read_text()
  assert "include.plugins, coroutines.cmk" in demo
  assert "cmk_pragma" not in demo
