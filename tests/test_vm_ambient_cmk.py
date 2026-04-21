"""Contract for `_vm.ambient` -- the unsupervised ambient-isolation primitive
(virtual-machine.cmk), the substrate under fork / reflect-fork.

`_vm.ambient <key>` is an env-prefix that runs a goal in a fresh, caller-keyed VM
namespace: it re-keys K (CONTROL_STACK_FRAMES) and E (via MAKE_SUPER -> vmenv) onto
<key>, with CMK_SUPERVISOR=0 so the child has no trampoline and its files survive
the join for harvest.

These pin the primitive BOTH directions:
  - the child writes to its OWN keyed K/E (isolation is real, not a no-op);
  - the caller's K is UNTOUCHED by the child (no bleed);
  - the child's files SURVIVE the child exit (no teardown), so the caller can harvest.

Marked `unit` + `external_module` (no docker; needs the virtual-machine.cmk plugin).
"""

import json
import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# A minimal file that drives _vm.ambient directly: the parent pushes one K frame,
# spawns a child in an isolated ambient (which pushes its OWN frame + sets an E var),
# then prints its own K back plus the child's key so the test can inspect the
# child's surviving files.
FIXTURE = r"""#!/usr/bin/env -S ./compose.mk cmk run
$(call include.plugins, virtual-machine.cmk)

child.work:
  printf '{"who":"child"}' | ${control_stack.frame.push}
  $(call __vm__.setenv, marker, child_was_here)

ambient.demo:
  run="$${MAKE_SUPER:-$$$$}"; \
  printf '{"who":"parent"}' | ${control_stack.frame.push}; \
  key="$${run}.child"; \
  $(call _vm.ambient,$$key) ${make} child.work; \
  printf 'PARENT_K=%s\n' "`${control_stack.frames} | ${jq.run} -c .`"; \
  printf 'CHILD_KEY=%s\n' "$${key}"

__main__: ambient.demo
"""


def _strip(text):
  return re.sub(r"\x1b\[[0-9;]*m", "", text)


@pytest.fixture
def ambient_run(tmp_path):
  """Run the fixture once; yield (parent_k, child_key); clean up surviving child files."""
  fixture = tmp_path / "vm_ambient_fixture.cmk"
  fixture.write_text(FIXTURE)
  env = {**os.environ, "NO_COLOR": "1"}
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(fixture)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, env=env,
    capture_output=True, text=True, errors="replace", timeout=180,
  )
  out = _strip(r.stdout + r.stderr)
  assert r.returncode == 0, f"fixture failed (rc={r.returncode}):\n{out}"
  m_k = re.search(r"^PARENT_K=(.*)$", out, re.M)
  m_key = re.search(r"^CHILD_KEY=(.*)$", out, re.M)
  assert m_k and m_key, f"fixture did not emit PARENT_K / CHILD_KEY:\n{out}"
  child_key = m_key.group(1).strip()
  child_k_file = REPO / f".tmp.CONTROL_STACK_FRAMES.{child_key}"
  child_e_file = REPO / f".tmp.cmk.vmenv.{child_key}"
  try:
    yield {
      "parent_k": json.loads(m_k.group(1).strip()),
      "child_key": child_key,
      "child_k_file": child_k_file,
      "child_e_file": child_e_file,
      "out": out,
    }
  finally:
    for f in (child_k_file, child_e_file):
      try:
        f.unlink()
      except FileNotFoundError:
        pass


def test_caller_K_is_untouched_by_the_child(ambient_run):
  # The parent's own K holds exactly its one frame -- the child's push landed in a
  # DIFFERENT (re-keyed) K, so it never bled into the caller.
  parent_k = ambient_run["parent_k"]
  whos = [frame.get("who") for frame in parent_k]
  assert whos == ["parent"], f"caller K polluted by the child ambient: {parent_k}"


def test_child_K_is_populated_in_its_own_keyed_file(ambient_run):
  # Isolation is not a no-op: the child really wrote its frame, into its own keyed K.
  kf = ambient_run["child_k_file"]
  assert kf.exists(), f"child K file missing (should survive the join): {kf}"
  child_k = json.loads(kf.read_text())
  whos = [frame.get("who") for frame in child_k]
  assert whos == ["child"], f"child K wrong (expected one child frame): {child_k}"


def test_child_E_is_populated_and_survives(ambient_run):
  # E (the CEK environment) is re-keyed via MAKE_SUPER; the child's setenv landed in
  # its own vmenv file, which survives (CMK_SUPERVISOR=0, no teardown).
  ef = ambient_run["child_e_file"]
  assert ef.exists(), f"child E file missing (should survive the join): {ef}"
  env = json.loads(ef.read_text())
  assert env.get("marker") == "child_was_here", f"child E wrong: {env}"
