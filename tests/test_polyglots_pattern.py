"""`code.import pattern=<glob>` -- bind EVERY define-block whose name matches
the glob to one interpreter, scaffolding a target per block (demos/code-objects-3.mk).

The glob runs over make's `.VARIABLES`, so `pattern=[.]py` scaffolds every `*.py`
define and nothing else.  Scaffolding (which blocks become targets) is a parse-time
fact, checked docker-free (`unit`); the end-to-end dispatch of the demo is
`needs_docker`.
"""

import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO3 = REPO / "demos" / "code-objects-3.mk"

# Three blocks: two match `[.]py`, one does not; plus a `.img` var that must NOT match.
FIXTURE = """include compose.mk
python.img=python:3.11-slim-bookworm
my_interp/%:; cat ${*}
define foo.py
print("foo-block")
endef
define bar.py
print("bar-block")
endef
define baz.sh
echo baz-block
endef
$(call code.import, pattern=[.]py bind=my_interp)
"""


def _make(mkdir, *targets, dry=False, timeout=120):
  argv = ["make", "-f", "Makefile"] + (["-n"] if dry else []) + list(targets)
  return subprocess.run(
    argv, cwd=str(mkdir), capture_output=True, text=True, errors="replace", timeout=timeout
  )


@pytest.mark.unit
def test_pattern_scaffolds_only_matching_blocks(tmp_path):
  (tmp_path / "Makefile").write_text(FIXTURE)
  (tmp_path / "compose.mk").write_bytes(COMPOSE.read_bytes())
  # each `.py` block became a real (dispatchable) target -- dry-run, no docker.
  assert _make(tmp_path, "foo.py", dry=True).returncode == 0
  assert _make(tmp_path, "bar.py", dry=True).returncode == 0
  # the `.sh` block is NOT scaffolded by the `.py` glob (no over-reach).
  r = _make(tmp_path, "baz.sh", dry=True)
  assert "No rule to make target" in r.stderr, r.stderr
  # and a same-stem-prefix var (`python.img`) is not swept in either.
  r = _make(tmp_path, "python.img", dry=True)
  assert "No rule to make target" in r.stderr, r.stderr


@pytest.mark.unit
def test_pattern_scaffolds_per_block_run_target(tmp_path):
  # each matched block gets the code.unbound seam (`.run/%`, `.to.file`, ..), so
  # the glob really did run `code.unbound` per block -- probe one seam docker-free.
  (tmp_path / "Makefile").write_text(FIXTURE)
  (tmp_path / "compose.mk").write_bytes(COMPOSE.read_bytes())
  assert _make(tmp_path, "foo.py.to.file", dry=True).returncode == 0
  assert _make(tmp_path, "bar.py.to.file", dry=True).returncode == 0


@pytest.mark.integration
@pytest.mark.needs_docker
def test_code_objects_3_pattern_runs_every_block():
  # the demo binds one.py + two.py via `pattern=[.]py`; running both proves the glob
  # scaffolded AND dispatched each matched block through the single custom interpreter.
  r = subprocess.run(
    [str(DEMO3), "one.py", "two.py"],
    cwd=str(REPO),
    capture_output=True,
    text=True,
    errors="replace",
    timeout=400,
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "linux" in out, out                      # one.py -> sys.platform
  assert "hello world" in out, out                # two.py
  assert "count0" in out and "count2" in out, out  # two.py loop body
