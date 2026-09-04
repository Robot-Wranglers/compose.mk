"""`.INTERMEDIATE` glob hygiene: it must stay scoped to `.tmp.*.mk`, never bare `.tmp.*`.

GNU make wildcard-expands the prerequisites of a special target like `.INTERMEDIATE`
at every parse -- and compose.mk re-parses itself recursively (once per `${make}`
sub-call).  A bare `.tmp.*` glob therefore holds EVERY leaked `mktemp ./.tmp.XXXX`
scratch file as an intermediate prerequisite, so make's resident memory (and readdir
work) grows in proportion to the number of stale scratch files in the cwd -- a
self-reinforcing slowdown exactly when scratch accumulates.

Only `.mk`-suffixed `.tmp.*` files (the hosted cache `.tmp.hosted.*.mk` and staged
modules `.tmp.module.*.mk`) are ever make targets, so scoping the glob to `.tmp.*.mk`
preserves behavior for every file `.INTERMEDIATE` can affect on any make version, while
excluding the unbounded extension-less scratch.  These tests pin that scope so it is not
"simplified" back to `.tmp.*`.
"""

import re
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _intermediate_line() -> str:
  for line in COMPOSE_MK.read_text().splitlines():
    if line.startswith(".INTERMEDIATE:"):
      return line
  raise AssertionError("no `.INTERMEDIATE:` declaration found in compose.mk")


def test_intermediate_scoped_to_mk_not_bare_tmp():
  # regression guard: the glob is `.tmp.*.mk`, and NO bare `.tmp.*` token remains.
  line = _intermediate_line()
  assert ".tmp.*.mk" in line, line
  # a bare `.tmp.*` (glob not immediately followed by `.mk`) reopens the O(n-scratch)
  # memory blowup -- forbid it.
  assert not re.search(r"\.tmp\.\*(?!\.mk)", line), (
    "bare `.tmp.*` glob reintroduced (unbounded scratch -> make RSS grows): " + line
  )


def test_intermediate_glob_excludes_scratch_includes_mk(cmk, tmp_path):
  # Behavioral, version-agnostic: run compose.mk's ACTUAL `.INTERMEDIATE` line in
  # isolation and confirm its parse-time wildcard expansion excludes extension-less
  # scratch while still catching `.mk`-suffixed staged/remade makefiles.  `make -pq`
  # prints the database (with the globbed special-target prereqs) without executing.
  probe = tmp_path / "probe.mk"
  probe.write_text(_intermediate_line() + "\nall:;@true\n")
  for i in range(5):
    (tmp_path / f".tmp.scratch{i}").write_text("")  # like io.mktemp `./.tmp.XXXX`
  (tmp_path / ".tmp.hosted.deadbeef.mk").write_text("")  # a staged/remade makefile
  r = cmk("-pq", makefile=str(probe), cwd=tmp_path)
  expanded = " ".join(
    ln for ln in r.stdout.splitlines() if ln.startswith(".INTERMEDIATE:")
  )
  assert expanded, r.stdout[:400]
  assert ".tmp.hosted.deadbeef.mk" in expanded, expanded
  for i in range(5):
    assert f".tmp.scratch{i}" not in expanded, expanded
