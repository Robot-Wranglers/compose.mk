"""JSON contract for dunder OBSERVER targets.

Every self-model target that is *meant* to be a JSON snapshot must emit LEGAL JSON in both live and idle
states -- never an empty string (which would break any downstream `jq` / `json.loads`).  This pins the
reflective surface of the triad: `__pragma__` (compose.mk) and `__vm__` / `.snapshot` / `.stack` /
`.kontinuation` / `.frames` (the virtual-machine plugin).  Each name doubles as a macro (`${__vm__.x}`,
embed) and a target (`${make} __vm__.x`, display) -- no `.show` suffix.

Scalar projections (`__vm__.ip` / `.control`, bare goal name) and the `.backtrace` tree are DELIBERATELY
not JSON and are not asserted here.  Regression guard: `${__vm__}` used to `exit 0` (empty) when idle; it
now degrades to `{}`, so the snapshot contract is total.
"""

import json
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
VM_DEMO = REPO / "demos" / "vm.mk"

# (target, expected container type) -- every entry must parse; the type pins {} (object) vs [] (array).
PRAGMA_OBSERVERS = [("__pragma__", dict)]
VM_OBSERVERS = [
  ("__vm__", dict),
  ("__vm__.snapshot", dict),
  ("__vm__.stack", list),
  ("__vm__.kontinuation", list),
  ("__vm__.frames", dict),
]


def _stdout(argv):
  # check=False: observer goals may exit non-zero (no __main__), but stdout carries the payload.
  r = subprocess.run(
    argv,
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=90,
  )
  return r.stdout.strip()


@pytest.mark.parametrize("target,typ", PRAGMA_OBSERVERS)
def test_pragma_observer_is_legal_json(target, typ):
  out = _stdout([str(COMPOSE), target])
  assert out, f"{target} emitted EMPTY -- not legal JSON"
  v = json.loads(out)  # raises (test fails) on empty/garbage
  assert isinstance(v, typ), (out, type(v).__name__)


@pytest.mark.parametrize("target,typ", VM_OBSERVERS)
def test_vm_observer_is_legal_json_when_idle(target, typ):
  # IDLE: invoked standalone with no machine running -> must STILL parse ({} / []), never "".
  # This is the exact case that regressed before the idle-degrade fix.
  out = _stdout([str(VM_DEMO), target])
  assert out, (
    f"{target} emitted EMPTY when idle -- the snapshot must degrade to legal JSON, not ''"
  )
  v = json.loads(out)
  assert isinstance(v, typ), (out, type(v).__name__)


def test_vm_snapshot_is_legal_json_when_live():
  # LIVE: `self.demo` prints `${__vm__}` mid-run (self.report keeps K non-empty).  The self-model line
  # must be parseable JSON -- proving the snapshot is legal JSON while the machine is actually running.
  r = subprocess.run(
    [str(VM_DEMO), "self.demo"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=90,
  )
  out = r.stdout + r.stderr
  line = next(
    (ln for ln in out.splitlines() if ln.strip().startswith("self-model")),
    None,
  )
  assert line, out
  payload = line.split(":", 1)[
    1
  ].strip()  # maxsplit=1: keep the JSON's own colons intact
  v = json.loads(payload)
  assert isinstance(v, dict), (payload, type(v).__name__)


REGISTERS = ("__ip__", "__alt__", "__yielded__", "__step__", "__step_budget__", "__posix_code__", "__exit_code__")


def test_scheduler_registers_defined_unsupervised():
  # Read from plain make (no compose.mk supervisor -- `make -f` parses it as a pure makefile), the
  # registers are DEFINED (empty) via their `?=` defaults: the observer echoes empty and a
  # --warn-undefined-variables parse never flags them (the invariant that keeps `$(__ip__)` safe in
  # a user makefile that includes compose.mk).
  r = subprocess.run(
    ["make", "-f", str(COMPOSE), "--warn-undefined-variables", "__ip__"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=90,
  )
  assert r.stdout.strip() == "", r.stdout  # defined but empty, no machine running
  warns = [
    ln for ln in r.stderr.splitlines()
    if "undefined variable" in ln and any(reg in ln for reg in REGISTERS)
  ]
  assert not warns, r.stderr


def test_snapshot_reads_scheduler_registers():
  # `__vm__.snapshot` single-sources the scheduler registers: a LIVE snapshot carries the register
  # cells `step` / `posix_code` / `exit_code` (the raw-vs-resolved code channels surfaced
  # separately), with `step` a positive int.  Reuses the live self.demo snapshot line.
  r = subprocess.run(
    [str(VM_DEMO), "self.demo"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    timeout=90,
  )
  out = r.stdout + r.stderr
  line = next(
    (ln for ln in out.splitlines() if ln.strip().startswith("self-model")), None
  )
  assert line, out
  v = json.loads(line.split(":", 1)[1].strip())
  for key in ("step", "posix_code", "exit_code"):
    assert key in v, (key, v)
  assert isinstance(v["step"], int) and v["step"] >= 1, v
