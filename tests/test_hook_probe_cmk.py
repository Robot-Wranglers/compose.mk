"""flux.pre/% + flux.post/% hook-probe fast-skip.

The per-goal pre/post hook dispatchers used to run ``make -q <goal>.pre`` -- a
full re-parse of compose.mk -- just to answer "does a hook target exist?".  When
no ``.pre``/``.post`` hook is defined anywhere in the loaded makefiles (the
overwhelmingly common case) that reparse is pure waste, so the dispatcher now
grep-gates it: it only spawns the ``make -q`` probe when a hook-target line
actually exists in ``MAKEFILE_LIST``.  These tests pin BOTH halves of the
contract -- hooks still dispatch when present, and the probe is elided when
absent (no extra reparse).  Pure local make -- no docker.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrap(tmp_path, body=""):
  mk = tmp_path / "Makefile"
  mk.write_text("include %s\n%s" % (COMPOSE_MK, body))
  return mk


# --- dispatch when a hook is present ----------------------------------------


def test_pre_hook_dispatched_when_present(cmk, tmp_path):
  mk = _wrap(tmp_path, "foo.pre:; @echo PRE-RAN\n")
  r = cmk("flux.pre/foo", makefile=mk, cwd=tmp_path)
  assert r.ok, r.stderr
  assert "PRE-RAN" in r.stdout, (r.stdout, r.stderr)


def test_post_hook_dispatched_when_present(cmk, tmp_path):
  mk = _wrap(tmp_path, "foo.post:; @echo POST-RAN\n")
  r = cmk("flux.post/foo", makefile=mk, cwd=tmp_path)
  assert r.ok, r.stderr
  assert "POST-RAN" in r.stdout, (r.stdout, r.stderr)


# --- clean skip when no hook exists -----------------------------------------


def test_pre_skipped_cleanly_when_absent(cmk, tmp_path):
  r = cmk("flux.pre/bar", makefile=_wrap(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr  # no error, no dispatch


def test_post_skipped_cleanly_when_absent(cmk, tmp_path):
  r = cmk("flux.post/bar", makefile=_wrap(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr


def test_unrelated_hook_does_not_dispatch_wrong_goal(cmk, tmp_path):
  # A hook for goal `foo` must not fire for goal `baz` (grep gate passes because a
  # `.pre:` line exists, but `make -q baz.pre` correctly finds nothing to dispatch).
  mk = _wrap(tmp_path, "foo.pre:; @echo FOO-PRE\n")
  r = cmk("flux.pre/baz", makefile=mk, cwd=tmp_path)
  assert r.ok, r.stderr
  assert "FOO-PRE" not in r.stdout, r.stdout


# --- the fast-skip actually elides the reparse ------------------------------


def _make_execs(mk, cwd, *args):
  """Count successful make execve(2) across the tree for `make -f mk <args>`."""
  fd, tp = tempfile.mkstemp(suffix=".strace")
  os.close(fd)
  try:
    subprocess.run(
      ["strace", "-f", "-qq", "-e", "trace=execve", "-o", tp,
       "make", "-f", str(mk), *args],
      cwd=str(cwd),
      env={**os.environ, "NO_COLOR": "1", "CMK_INTERNAL": "1",
           "CMK_DISABLE_HOOKS": "1", "TERM": "dumb"},
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
    )
    return sum(
      1
      for ln in Path(tp).read_text(errors="replace").splitlines()
      if re.search(r"=\s*0\s*$", ln) and re.search(r'execve\("[^"]*/make"', ln)
    )
  finally:
    Path(tp).unlink(missing_ok=True)


@pytest.mark.skipif(shutil.which("strace") is None, reason="strace unavailable")
def test_absent_hook_spawns_no_probe_reparse(tmp_path):
  # No hook anywhere -> the grep gate short-circuits, so flux.pre/<x> must NOT
  # spawn the `make -q <x>.pre` sub-make (the reparse this optimization removes).
  mk = _wrap(tmp_path)
  assert _make_execs(mk, tmp_path, "flux.pre/bar") == 1, (
    "flux.pre with no hooks should not fork a `make -q` reparse"
  )


@pytest.mark.skipif(shutil.which("strace") is None, reason="strace unavailable")
def test_present_hook_does_probe_and_dispatch(tmp_path):
  # A real hook -> the gate passes, so the probe + dispatch sub-makes DO run
  # (more than the single top-level make), proving the gate is not over-eager.
  mk = _wrap(tmp_path, "foo.pre:; @echo PRE\n")
  assert _make_execs(mk, tmp_path, "flux.pre/foo") > 1, (
    "flux.pre with a hook present should probe + dispatch"
  )
