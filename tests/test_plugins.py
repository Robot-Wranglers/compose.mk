"""Plugin suite: every shipped `.cmk/` plugin loads + exposes its public surface.

This is the explicit `plugin`-marked entrypoint (`make plugin-test` / `tox -e plugin`).  It:

  (a) smoke-tests that EVERY plugin under `.cmk/` imports cleanly via `include.plugins` against the
      CURRENT `compose.mk` -- the regression guard that catches a core API rename breaking a plugin,
      including the standalone ones (`py.mk`/`actions.mk`/`docs.mk`/`json.cmk`/`pdoc.mk`) that have no
      other coverage; and
  (b) asserts each plugin contributes at least one public target or macro, auto-derived by diffing
      the make database with vs. without the plugin -- so a newly-dropped plugin is covered with no
      edit to this file, while a plugin that fails to import or adds nothing still trips the suite.

Richer per-plugin BEHAVIOR is covered by the dedicated `plugin`-marked suites -- `test_repl_*`
(tux.repl.cmk), `test_vm_*` (virtual-machine.cmk), `test_polyglot_*` (code.golang.cmk).  This file is the
pure-load layer (no docker): plugins are read from the real `.cmk/` but stage + scratch into the
pytest tmp dir, so the repo's `.cmk/` is never polluted.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.plugin

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
CMK_DIR = REPO / ".cmk"

# Every plugin under `.cmk/` EXCEPT the vendored core copy.  Discovered (not hard-coded) so a newly
# added plugin is automatically smoke-tested.
PLUGINS = sorted(
  p.name
  for p in CMK_DIR.iterdir()
  # real plugins only: skip the vendored core copy and any dot-prefixed staging/temp artifacts
  # (`.tmp.module.*`, `.tmp.plugin.*`) that may linger in the dir.
  if p.suffix in (".mk", ".cmk")
  and p.name != "compose.mk"
  and not p.name.startswith(".")
)

# Matches a defined public symbol in a `make -pn` database dump: a target (`name:`, not `name:=`) or a
# macro (`name =` / `name :=` / `define name`).  Recipe lines are tab-indented so the `^` anchor skips
# them.  Leading-`_`/`.` names are filtered by the caller as internal.
_SYM_RE = re.compile(
  r"(?m)^(?:define\s+)?([A-Za-z][\w./%+-]*)\s*(?::(?!=)|:?:?=|\+=|\?=)"
)


def _symbols(pn_stdout):
  # Set of every target/macro name make reports as defined.
  return set(_SYM_RE.findall(pn_stdout))


def _wrapper(tmp_path, plugin, name="wrap.mk"):
  mk = tmp_path / name
  mk.write_text(
    f"include {COMPOSE}\n"
    f"$(call include.plugins, {plugin})\n"
    f"probe:; @echo PLUGIN_LOADED\n"
  )
  return mk


def _baseline_wrapper(tmp_path, name="base.mk"):
  # Same file MINUS the plugin include -- the control for the DB diff.
  mk = tmp_path / name
  mk.write_text(f"include {COMPOSE}\nprobe:; @echo PLUGIN_LOADED\n")
  return mk


def _make(mk, *args, timeout=180, env=None):
  # plugins are FOUND in the real .cmk (CMK_PLUGINS_DIR) but STAGED + scratch into the tmp cwd
  # (CMK_MODULES_DIR + cwd), so the repo's .cmk/ stays clean.
  env = {
    **(env or os.environ),
    "CMK_PLUGINS_DIR": str(CMK_DIR),
    "CMK_MODULES_DIR": str(mk.parent),
    "NO_COLOR": "1",
  }
  return subprocess.run(
    ["make", "-f", str(mk), *args],
    cwd=str(mk.parent),
    capture_output=True,
    text=True,
    errors="replace",
    env=env,
    timeout=timeout,
  )


def _defined_symbols(mk):
  # The set of target/macro NAMES make reports as defined for this wrapper, via a `-pn` database dump.
  # Warm the content-keyed hosted cache with a NORMAL run first: `-pn` (`--dry-run`) leaks through
  # MAKEFLAGS into the hosted-partition build sub-make, which on a COLD cache writes a database dump
  # into the cache instead of compiled code and corrupts it.  With the cache already warm, `-pn` only
  # reads it.  The explicit `probe` target keeps the dry-run from trying to build the default goal.
  _make(mk, "probe")
  return _symbols(_make(mk, "-pn", "probe").stdout)


@pytest.fixture(scope="module")
def baseline_symbols(tmp_path_factory):
  # Symbols defined by a bare `include compose.mk` -- computed once; every plugin diffs against it.
  return _defined_symbols(_baseline_wrapper(tmp_path_factory.mktemp("baseline")))


@pytest.mark.parametrize("plugin", PLUGINS)
def test_plugin_imports_cleanly(plugin, tmp_path):
  # Imports via include.plugins against the CURRENT compose.mk -- no missing/parse/recursion errors.
  r = _make(_wrapper(tmp_path, plugin), "probe")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "PLUGIN_LOADED" in out, out
  assert "CMK_INCLUDE_MISSING" not in out, out


@pytest.mark.parametrize("plugin", PLUGINS)
def test_plugin_contributes_public_surface(plugin, tmp_path, baseline_symbols):
  # Auto-derived (no curated list): a plugin must add at least one PUBLIC (non-`_`/`.`) target or macro
  # over the bare `include compose.mk` baseline.  Diffing the two make-database dumps cancels out
  # everything compose.mk already defines, leaving only the plugin's own contribution.  A newly-dropped
  # plugin is covered with zero edits here; one that imports but exports nothing public still trips.
  added = {s for s in _defined_symbols(_wrapper(tmp_path, plugin)) - baseline_symbols if s[0] not in "_."}
  assert added, f"{plugin} imported but contributed no public target/macro"


def test_plugin_with_hosted_dsl_kinds_on_cold_hosted_cache(tmp_path):
  # Regression: the `dsl.jqlang`/`dsl.awklang` KINDS are minted by the `__hosted__` partition, which
  # loads via makefile-remaking AFTER the first parse pass.  A plugin that mints instances with those
  # kinds qualified (`dsl.jqlang <name>(| .. |)`) evaluated at parse-time (during include.plugins) on
  # a COLD hosted cache must not hard-error before make can remake+restart: the kind macro is a no-op
  # in the pre-remake window, make rebuilds the cache, restarts, and the second pass mints.  (`dsl` is
  # reached as a `cmk` prelude member, `from cmk import dsl`; it is not an openable module.)  Force
  # cold via a private, empty HOSTED_CACHE_DIR so this run cannot ride a warm shared cache.
  cache = tmp_path / "hosted-cache"
  cache.mkdir()
  env = {**os.environ, "HOSTED_CACHE_DIR": str(cache)}
  r = _make(_wrapper(tmp_path, "gitops.cmk"), "probe", env=env)
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "PLUGIN_LOADED" in out, out
  assert "is not a member of module" not in out, out
