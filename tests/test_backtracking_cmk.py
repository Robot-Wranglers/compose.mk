"""Characterization of the __vm__ CHOICE / BACKTRACK machinery (demos/cmk/unicon-queens.cmk).

Icon-style goal-directed evaluation on the CEK machine: `vm.choose "a b c"` records a
`kind:"choice"` frame holding the untried alternatives (`alts`) and runs the first; a
`vm.backtrack` (Icon expression failure) unwinds K to the nearest choice frame that still has
an untried alt, restores its env (the CEK trail), consumes one alt, and resumes -- classic DFS.

These pin the OBSERVABLE semantics -- the alternation generator, the first-alt-first DFS
solution order, and whole-search exhaustion.  The demo's frontier is now expressed as lifted
`goal` values (`goal Q = q`; `$(Q)/<cols>` reifies to `q/<cols>`, TODO-reflective-tower); the
section property (`compile(goal(t)) == t`) makes that swap semantics-preserving, so these outputs
did NOT move -- this file is the safety net that proves it.

Marked `unit` + `plugin` (no docker; needs the virtual-machine.cmk plugin).
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.external_module, pytest.mark.covers_demo("unicon-queens.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "unicon-queens.cmk"


def _run(*goals, nq=None, timeout=240):
  env = {**os.environ, "NO_COLOR": "1"}
  if nq is not None:
    env["NQ"] = str(nq)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *goals],
    cwd=str(REPO), stdin=subprocess.DEVNULL, env=env,
    capture_output=True, text=True, errors="replace", timeout=timeout,
  )
  return r, re.sub(r"\x1b\[[0-9;]*m", "", r.stdout + r.stderr)


def _board_columns(out):
  """Parse the rendered board (lines of `. Q . .`) into the per-row column list."""
  cols = []
  for ln in out.splitlines():
    cells = ln.strip().split()
    if cells and "Q" in cells and all(c in (".", "Q") for c in cells):
      cols.append(cells.index("Q"))
  return cols


def _valid_queens(cols):
  n = len(cols)
  if n == 0 or len(set(cols)) != n:
    return False
  return all(
    abs(cols[i] - cols[j]) != abs(i - j)
    for i in range(n) for j in range(i + 1, n)
  )


# ---- the frontier is a lifted goal ----------------------------------------------------------

def test_frontier_is_expressed_as_a_lifted_goal():
  # The frontier routes through the __goals__ lift, not a raw target-name blob: the demo declares
  # `goal Q = q` (Icon bare-abstraction generator) and both builders emit `$(Q)/<cols>` (which
  # reifies to `q/<cols>`, so the DFS outputs pinned below are unchanged).
  src = DEMO.read_text()
  assert re.search(r"^goal\s+Q\s*=\s*q\s*$", src, re.M), "demo must declare `goal Q = q`"
  assert "$(Q)/" in src, "frontier builders must use the lifted goal $(Q)/"
  assert "q/$$c" not in src, "raw target-name frontier (q/$$c) should be gone"


# ---- alternation: the choose -> backtrack resume cycle --------------------------------------

def test_warmup_alternation_resumes_every_alt():
  # vm.choose(w/one w/two w/three) runs the first branch; each branch fails (vm.backtrack),
  # resuming the choice frame with the next untried alt -- so all three are produced (Icon
  # `every`).
  r, out = _run("warmup")
  assert r.returncode == 0, out
  for word in ("one", "two", "three"):
    assert f"produced: {word}" in out, out


def test_warmup_order_is_first_alt_first_dfs():
  # the resume order is exactly the alternation order (first-alt-first DFS) -- the ordering
  # invariant the goals refactor must preserve.
  r, out = _run("warmup")
  produced = re.findall(r"produced: (\w+)", out)
  assert produced == ["one", "two", "three"], produced


# ---- n-queens: deep nested backtracking + env restore ---------------------------------------

def test_queens_finds_valid_solution():
  # each row is an alternation of safe columns; a dead end (no safe column) fails and unwinds
  # to the previous row's next choice, restoring the board via the frame's env snapshot.
  r, out = _run("queens", nq=6)
  assert r.returncode == 0, out
  cols = _board_columns(out)
  assert len(cols) == 6, out
  assert _valid_queens(cols), cols


def test_queens_first_solution_is_deterministic():
  # DFS first-alt-first over a fixed column order => a stable FIRST solution.
  r, out = _run("queens", nq=6)
  assert _board_columns(out) == [1, 3, 5, 0, 2, 4], out


def test_queens_small_board_exhaustive_backtracking():
  # 4-queens: row0 col0 leads to a dead end, so the search backtracks past it to col1 before
  # succeeding -- exercising the unwind + env-restore on a board small enough to reason about.
  r, out = _run("queens", nq=4)
  assert _board_columns(out) == [1, 3, 0, 2], out
  assert "1.3.0.2" in out, out   # the demo also logs the placement dot-joined


def test_no_solution_exhausts_the_search():
  # 3-queens has no solution: the search unwinds every choice frame and reports exhaustion
  # (Icon whole-expression failure), emitting no board.
  r, out = _run("queens", nq=3)
  assert r.returncode == 0, out
  assert "search exhausted" in out, out
  assert _board_columns(out) == [], out


# ---- the whole tour: exhaustion falls through to the next scheduled goal ---------------------

def test_full_tour_warmup_falls_through_to_queens():
  # __main__ schedules `warmup queens`; warmup's exhaustion (no more alts) does not abort --
  # control falls through the continuation to queens, which then searches.  Proves exhaustion
  # is a normal transfer, not a hard failure.
  r, out = _run(nq=6)
  assert r.returncode == 0, out
  assert "produced: three" in out, out          # warmup ran to exhaustion
  assert _valid_queens(_board_columns(out)), out  # then queens found a solution
