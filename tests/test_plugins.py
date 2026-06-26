"""Plugin suite: every shipped `.cmk/` plugin loads + exposes its public surface.

This is the explicit `plugin`-marked entrypoint (`make plugin-test` / `tox -e plugin`).  It:

  (a) smoke-tests that EVERY plugin under `.cmk/` imports cleanly via `include.plugins` against the
      CURRENT `compose.mk` -- the regression guard that catches a core API rename breaking a plugin,
      including the standalone ones (`py.mk`/`actions.mk`/`docs.mk`/`json.mk`/`pdoc.mk`) that have no
      other coverage; and
  (b) asserts a representative public symbol (target or macro) from each survives the import.

Richer per-plugin BEHAVIOR is covered by the dedicated `plugin`-marked suites -- `test_repl_*`
(tux.repl.cmk), `test_vm_*` (virtual-machine.cmk), `test_polyglot_*` (polyglot.golang.cmk).  This file is the
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

# A representative public symbol (target or macro) each plugin must contribute once imported.
SURFACE = {
  "virtual-machine.cmk": "control_stack",
  "coroutines.cmk": "coroutines.demo",
  "json.mk": "json.validate",
  "py.mk": "pip.install",
  "actions.mk": "actions.lint",
  "docs.mk": "css.minifier",
  "pdoc.mk": "pdoc",
  "polyglot.golang.cmk": "polyglot.golang.lambda",
  "tux.repl.cmk": "tux.repl",
}


def _wrapper(tmp_path, plugin):
  mk = tmp_path / "wrap.mk"
  mk.write_text(
    f"include {COMPOSE}\n"
    f"$(call include.plugins, {plugin})\n"
    f"probe:; @echo PLUGIN_LOADED\n"
  )
  return mk


def _make(mk, *args, timeout=180):
  # plugins are FOUND in the real .cmk (CMK_PLUGINS_DIR) but STAGED + scratch into the tmp cwd
  # (CMK_MODULES_DIR + cwd), so the repo's .cmk/ stays clean.
  env = {
    **os.environ,
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


@pytest.mark.parametrize("plugin", PLUGINS)
def test_plugin_imports_cleanly(plugin, tmp_path):
  # Imports via include.plugins against the CURRENT compose.mk -- no missing/parse/recursion errors.
  r = _make(_wrapper(tmp_path, plugin), "probe")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "PLUGIN_LOADED" in out, out
  assert "CMK_INCLUDE_MISSING" not in out, out


@pytest.mark.parametrize("plugin", PLUGINS)
def test_plugin_exposes_public_surface(plugin, tmp_path):
  # A representative public symbol survives the import -- asserted against the make database dump
  # (`-pn`), which lists both targets (`name:`) and macros (`name =` / `define name`).
  sym = SURFACE[plugin]
  r = _make(_wrapper(tmp_path, plugin), "-pn")
  assert re.search(rf"(?m)^(define ){{0,1}}{re.escape(sym)}\b", r.stdout), (
    f"{sym!r} not defined after importing {plugin}\n{r.stderr[-2000:]}"
  )


def test_every_shipped_plugin_has_surface_coverage():
  # Guard: a newly-added plugin must get a SURFACE entry, so it can never be silently un-asserted.
  missing = [p for p in PLUGINS if p not in SURFACE]
  assert not missing, (
    f"plugins missing a curated public symbol in SURFACE: {missing}"
  )
