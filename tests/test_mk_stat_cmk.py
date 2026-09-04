"""Contract test for `mk.stat` after its move into the `__hosted__` partition.

`mk.stat` is now authored in cmk-lang: a raw `jqlang mk.stat.shape(| .. |)` (a
pure-jq shape read from `.`) fed by a `jb`-built typed input (`:number` for the
makelevel, `:raw` for the pragma manifest).  It deliberately does NOT use
`.locals()` -- core can't assume the `target_locals` pragma.  This pins the JSON
shape + types so the hosted rewrite (and the jb-detection path) can't silently
drift.

Docker-free when `jb` is installed (`jb.init`); otherwise the dockerized jb
fallback is exercised, which is why this runs under the default timeout.
"""

import json
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _stat():
  p = subprocess.run(
    [str(COMPOSE), "mk.stat"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return p


def test_mk_stat_emits_valid_json_with_expected_keys():
  p = _stat()
  assert p.returncode == 0, p.stdout + p.stderr
  doc = json.loads(p.stdout)
  assert set(doc) == {
    "make_version", "version", "compose.mk", "bin", "makelevel",
    "plugins", "modules", "n_plugins", "n_modules", "pragma",
  }


def test_mk_stat_types_are_coerced():
  # jb `:number`/`:raw` + the jq shape give real types, not stringified ones.
  doc = json.loads(_stat().stdout)
  assert isinstance(doc["makelevel"], int)        # :number
  assert isinstance(doc["pragma"], dict)          # :raw JSON object
  assert isinstance(doc["plugins"], list)         # `words` split, not a string
  assert isinstance(doc["modules"], list)
  assert isinstance(doc["n_plugins"], int)
  assert isinstance(doc["n_modules"], int)


def test_mk_stat_registry_counts_match_arrays():
  doc = json.loads(_stat().stdout)
  assert doc["n_plugins"] == len(doc["plugins"])
  assert doc["n_modules"] == len(doc["modules"])
