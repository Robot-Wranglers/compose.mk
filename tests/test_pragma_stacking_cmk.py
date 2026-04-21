"""Tests for two-pass pragma stacking: the `plugin_pragma_allowed` pragma + `CMK_IMPORT_DISCOVER`.

When an ENTRY program sets `# cmk_pragma ::: { "plugin_pragma_allowed": true } :::`, the compiler runs
a TWO-PASS compile: a register-only discovery pass (`CMK_IMPORT_DISCOVER=1`, no module code-gen) finds
which plugins the entry imports, each plugin's `# cmk_pragma` header is merged into the entry's --
STRICTLY ADDITIVE (any key present in more than one merge-candidate is a HARD ERROR; no updates) -- and
the entry is then compiled with the merged pragma set.  So a plugin can alter the IMPORTER's
compilation.  This is proved here with a plugin whose `recipe_join` pragma changes the importer's
joinbody (`&&` -> `;`).  Without the gate pragma, plugins have NO compile influence (today's behavior).
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# A plugin that contributes a joinbody-affecting pragma (recipe_join), plus a trivial target so it is a
# valid plugin.
PLUGIN = '# cmk_pragma ::: { "recipe_join": ";" } :::\nnoop.tgt:; @true\n'
# An entry that opts into stacking and imports the plugin; `x` has a 2-line recipe whose join we inspect.
ENTRY = (
  '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
  "$(call include.plugins, joinpragma.cmk)\n"
  "x:\n\tc1\n\tc2\n"
)


def _compile(src, plugins_dir):
  env = {**os.environ, "CMK_PLUGINS_DIR": f"{plugins_dir}:.cmk"}
  return subprocess.run(
    [str(COMPOSE), "mk.compile"],
    cwd=str(REPO),
    input=src,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=90,
    env=env,
  )


def test_plugin_pragma_stacks_into_joinbody(tmp_path):
  # The headline: a plugin's `recipe_join: ";"` reaches the IMPORTER's joinbody because the entry
  # opted in with `plugin_pragma_allowed`.  Two-pass discovery + strict-additive merge made it happen.
  (tmp_path / "joinpragma.cmk").write_text(PLUGIN)
  r = _compile(ENTRY, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, (
    r.stdout
  )  # plugin's recipe_join=; drove the importer's joinbody
  assert "c1 && \\" not in r.stdout, r.stdout


def test_no_stacking_without_the_gate_pragma(tmp_path):
  # Same import, but the entry does NOT set plugin_pragma_allowed -> single-pass, plugin has zero
  # compile influence, default `&&` join (the pre-feature behavior; proves the gate is load-bearing).
  (tmp_path / "joinpragma.cmk").write_text(PLUGIN)
  entry = "$(call include.plugins, joinpragma.cmk)\nx:\n\tc1\n\tc2\n"
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 && \\" in r.stdout, r.stdout
  assert "c1 ; \\" not in r.stdout, r.stdout


def test_pragma_merge_conflict_is_a_hard_error(tmp_path):
  # Strict-additive: if the entry AND a plugin both set `recipe_join`, the key intersects -> the merge
  # is a hard error (no silent override), so the compile fails.
  (tmp_path / "joinpragma.cmk").write_text(PLUGIN)
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true, "recipe_join": "&&" } :::\n'
    "$(call include.plugins, joinpragma.cmk)\n"
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode != 0, r.stdout
  assert "conflict" in r.stderr.lower(), r.stderr


def test_stacking_works_via_prefix_import(tmp_path):
  # __plugins__.paths records the RESOLVED prefix path, so a plugin imported via `prefix=<dir>` (NOT on
  # CMK_PLUGINS_DIR) still contributes its pragma -- discovery reads its header at the recorded path.
  sub = tmp_path / "sub"
  sub.mkdir()
  (sub / "jp.cmk").write_text(
    PLUGIN
  )  # in sub/, which is NOT part of _compile's CMK_PLUGINS_DIR
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    f"$(call include.plugins, jp.cmk prefix={sub})\n"
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, (
    r.stdout
  )  # reached only via the recorded prefix path


def test_stacking_works_via_computed_import(tmp_path):
  # Discovery is compile-then-parse (imports evaluated for REAL), so a COMPUTED plugin name -- from a
  # variable defined in the entry -- is discovered.  A static/grep scan of the source would miss this.
  (tmp_path / "joinpragma.cmk").write_text(PLUGIN)
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    "PLUG := joinpragma.cmk\n"
    "$(call include.plugins, $(PLUG))\n"
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, (
    r.stdout
  )  # computed import resolved by real evaluation


def test_stacking_merges_multiple_plugins_additively(tmp_path):
  # N plugins each contributing a DIFFERENT key: the merge is an additive union, so BOTH reach the
  # importer (p1's recipe_join drives the joinbody; p2's custom_flag is injected).
  (tmp_path / "p1.cmk").write_text(
    '# cmk_pragma ::: { "recipe_join": ";" } :::\na.tgt:; @true\n'
  )
  (tmp_path / "p2.cmk").write_text(
    '# cmk_pragma ::: { "custom_flag": "9" } :::\nb.tgt:; @true\n'
  )
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    "$(call include.plugins, p1.cmk)\n"
    "$(call include.plugins, p2.cmk)\n"
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, r.stdout  # from p1
  assert "export CMK_PRAGMA_CUSTOM_FLAG := 9" in r.stdout, r.stdout  # from p2


def test_two_plugins_same_key_is_a_hard_error(tmp_path):
  # Strict-additive applies ACROSS plugins, not just entry-vs-plugin: two plugins both setting
  # recipe_join intersect on that key -> the merge is a hard error (no silent last-wins).
  (tmp_path / "p1.cmk").write_text(
    '# cmk_pragma ::: { "recipe_join": ";" } :::\na.tgt:; @true\n'
  )
  (tmp_path / "p2.cmk").write_text(
    '# cmk_pragma ::: { "recipe_join": "&&" } :::\nb.tgt:; @true\n'
  )
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    "$(call include.plugins, p1.cmk)\n"
    "$(call include.plugins, p2.cmk)\n"
    "x:; @true\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode != 0, r.stdout
  assert "conflict" in r.stderr.lower(), r.stderr


def test_discovered_plugin_without_pragma_is_skipped(tmp_path):
  # A discovered plugin that has NO cmk_pragma header contributes nothing to the merge (empty parse ->
  # skipped) and does not break stacking for the plugins that DO carry a header.
  (tmp_path / "p1.cmk").write_text(
    '# cmk_pragma ::: { "recipe_join": ";" } :::\na.tgt:; @true\n'
  )
  (tmp_path / "nop.cmk").write_text(
    "b.tgt:; @true\n"
  )  # no pragma header at all
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    "$(call include.plugins, p1.cmk)\n"
    "$(call include.plugins, nop.cmk)\n"
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, r.stdout


def test_gate_without_any_plugins_applies_entry_pragma(tmp_path):
  # Degenerate two-pass: `plugin_pragma_allowed` is set but the entry imports NO plugins.  Discovery
  # finds nothing, the merge is a no-op over just the entry, and the entry's OWN pragma still applies.
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true, "recipe_join": ";" } :::\n'
    "x:\n\tc1\n\tc2\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "c1 ; \\" in r.stdout, r.stdout


def test_stacking_array_valued_plugin_pragma(tmp_path):
  # A plugin can contribute a LIST-valued key; it merges and is emitted space-joined (like the compiler
  # already does for an array pragma) -- proving the merge is type-agnostic, not scalar-only.
  (tmp_path / "parr.cmk").write_text(
    '# cmk_pragma ::: { "cmk_post": ["p.x","p.y"] } :::\nc.tgt:; @true\n'
  )
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true } :::\n'
    "$(call include.plugins, parr.cmk)\n"
    "x:; @true\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, r.stderr
  assert "export CMK_PRAGMA_CMK_POST := p.x p.y" in r.stdout, r.stdout


@pytest.mark.xfail(
  strict=True,
  reason="LIST-typed pragmas (compiler_pre/post, cmk_pre/post) do NOT yet accumulate across two-pass "
  "stacking sources: the strict-additive merge (correct for scalars like recipe_join) treats a key set "
  "by BOTH the entry and a plugin as a hard conflict. A type-aware merge (union list knobs, replace-error "
  "scalar knobs) is the deferred fix; remove this marker when it lands.",
)
def test_list_pragma_accumulates_across_stacking_sources(tmp_path):
  # REPRO of the known gap. `compiler_pre` is a LIST knob (read via the accumulate resolver), so when the
  # entry AND an imported plugin both contribute to it, the two-pass merge SHOULD union them (+=), the
  # same way env+pragma already accumulate for a single program. Today it hard-errors instead:
  #   `cmk pragma merge conflict (additive-only, no updates) on keys: compiler_pre` (exit 2).
  # (Control -- entry compiler_pre + plugin compiler_POST, i.e. DIFFERENT keys -- already merges fine; it
  # is specifically the shared LIST key that wrongly conflicts.)
  (tmp_path / "plug.cmk").write_text(
    '# cmk_pragma ::: { "compiler_pre": ["pluginstage"] } :::\np.tgt:; @true\n'
  )
  entry = (
    '# cmk_pragma ::: { "plugin_pragma_allowed": true, "compiler_pre": ["entrystage"] } :::\n'
    "$(call include.plugins, plug.cmk)\n"
    "x:; @true\n"
  )
  r = _compile(entry, tmp_path)
  assert r.returncode == 0, (
    r.stderr
  )  # today: exit 2, merge conflict on `compiler_pre`
  # ...and both list contributions should survive into the merged manifest (order: entry then plugin).
  assert "entrystage" in r.stdout and "pluginstage" in r.stdout, r.stdout
