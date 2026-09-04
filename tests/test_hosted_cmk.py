"""Hosted/seed partition: a region of compose.mk authored in CMK-lang, lowered to a
content-addressed cache and bound via GNU make's makefile-remaking so a PLAIN
`include compose.mk` (no bash/supervisor) transparently gets it.

Pure local make -- no docker.  Exercised from a vanilla makefile that only
`include`s compose.mk, which is the whole point of the partition.
"""

import concurrent.futures
import os
import re
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _wrapper(tmp_path):
  # Pre-create .cmk so the hosted cache lands in the (writable, project-local) modules
  # dir here rather than the user XDG cache -- keeps the cache under tmp_path (asserted
  # below) and off the real ~/.cache. Mirrors a real project that has a ./.cmk.
  (tmp_path / ".cmk").mkdir(exist_ok=True)
  mk = tmp_path / "Makefile"
  mk.write_text("include %s\n__main__: hosted.selftest\n" % COMPOSE_MK)
  return mk


def _cache_files(tmp_path):
  d = tmp_path / ".cmk"
  return sorted(d.glob(".tmp.hosted.*.mk")) if d.exists() else []


def test_hosted_target_callable_from_vanilla_make(cmk, tmp_path):
  # The hosted `hosted.selftest` is authored in CMK-lang inside `define __hosted__`;
  # it must be reachable from a plain `include compose.mk` makefile.
  r = cmk("hosted.selftest", makefile=_wrapper(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr
  both = r.stdout + r.stderr
  assert "hosted partition is live" in both, both
  assert "ok" in r.stdout, r.stdout


def test_hosted_cache_is_built(cmk, tmp_path):
  cmk("hosted.selftest", makefile=_wrapper(tmp_path), cwd=tmp_path)
  files = _cache_files(tmp_path)
  assert len(files) == 1, (
    "expected exactly one hosted cache file, got %s" % files
  )


def test_hosted_cache_reused_not_rebuilt(cmk, tmp_path):
  mk = _wrapper(tmp_path)
  cmk("hosted.selftest", makefile=mk, cwd=tmp_path)
  before = _cache_files(tmp_path)
  assert before, "cache not built on first run"
  m0 = os.path.getmtime(before[0])
  # Second run: warm cache, no rebuild -> mtime unchanged.
  cmk("hosted.selftest", makefile=mk, cwd=tmp_path)
  after = _cache_files(tmp_path)
  assert [str(p) for p in after] == [str(p) for p in before], (
    "cache path churned"
  )
  assert os.path.getmtime(after[0]) == m0, "cache was rebuilt on a warm run"


def test_hosted_edit_rehashes_cache(cmk, tmp_path):
  # A region edit changes the content hash -> a NEW cache filename (old orphaned),
  # which is what lets the no-prerequisite remaking rule stay correct.
  mk = _wrapper(tmp_path)
  cmk("hosted.selftest", makefile=mk, cwd=tmp_path)
  first = _cache_files(tmp_path)[0].name
  # Simulate a different hosted region by pointing at a doctored compose.mk copy.
  doctored = tmp_path / "compose.mk"
  src = COMPOSE_MK.read_text().replace(
    "hosted partition is live", "hosted partition EDITED"
  )
  doctored.write_text(src)
  mk.write_text("include %s\n__main__: hosted.selftest\n" % doctored)
  cmk("hosted.selftest", makefile=mk, cwd=tmp_path)
  names = {p.name for p in _cache_files(tmp_path)}
  assert first in names, "original cache should still be present (orphaned)"
  assert len(names) >= 2, (
    "edited region should produce a new hash-named cache: %s" % names
  )


def test_hosted_cache_concurrent_cold_build_no_corruption(cmk, tmp_path):
  # Regression: N processes racing the same COLD hosted hash must not corrupt the
  # shared cache. The build writes a PID-keyed scratch temp and only promotes a
  # validated one (same idiom as `_mk.module.stage`).  Before that fix the recipe
  # shared a fixed-name `.build` temp and always `mv`'d it, so concurrent cold
  # builds interleaved / raced the rename -- surfacing as `mv: cannot stat`, a
  # truncated cache, and phantom `not a member` on the next parse.
  mk = _wrapper(tmp_path)  # pre-creates an EMPTY ./.cmk (cold) + wrapper Makefile
  n = 12
  with concurrent.futures.ThreadPoolExecutor(max_workers=n) as ex:
    results = list(
      ex.map(
        lambda _: cmk(
          "hosted.selftest", makefile=mk, cwd=tmp_path, timeout=120
        ),
        range(n),
      )
    )
  for i, r in enumerate(results):
    both = r.stdout + r.stderr
    assert r.ok, "worker %d rc=%d\n%s" % (i, r.returncode, both)
    assert "ok" in r.stdout, "worker %d missing ok:\n%s" % (i, both)
    for marker in ("not a member", "cannot stat", "No rule to make target"):
      assert marker not in both, "worker %d hit %r:\n%s" % (i, marker, both)
  files = _cache_files(tmp_path)
  assert len(files) == 1, "expected one cache file, got %s" % files
  n_targets = len(
    re.findall(r"(?m)^[A-Za-z_][A-Za-z0-9._/%-]*:", files[0].read_text())
  )
  assert n_targets >= 5, "cache looks truncated: %d targets" % n_targets
  assert not list((tmp_path / ".cmk").glob(".tmp.hosted.*.build")), (
    "scratch temp leaked"
  )


def test_hosted_parse_clean_under_warn_undefined(cmk, tmp_path):
  # --warn-undefined-variables is on in MAKEFLAGS; the partition must add no
  # undefined-variable warnings for its own HOSTED_*/__hosted__ symbols.
  r = cmk(
    "hosted.selftest",
    makefile=_wrapper(tmp_path),
    cwd=tmp_path,
    env={"MAKEFLAGS": "--warn-undefined-variables --no-print-directory"},
  )
  bad = [
    ln
    for ln in (r.stdout + r.stderr).splitlines()
    if "undefined variable" in ln
    and any(t in ln for t in ("HOSTED", "__hosted", "CMK_HOSTED"))
  ]
  assert not bad, bad


def test_mk_main_standalone_guard_routes_to_help(cmk):
  # mk.__main__ guard: the `-include`d hosted cache must NOT tip the standalone
  # (MAKEFILE_LIST count == 1) branch into the multi-file default-goal path.  Invoke
  # the guarded target directly (the `cmk` fixture runs supervisor-off, so a bare
  # no-arg invocation would take a different, unrelated bash branch).
  r = cmk("mk.__main__")
  assert r.ok, r.stderr
  assert "No rule to make target" not in (r.stdout + r.stderr), r.stderr


def test_include_mode_default_goal_runs(cmk, tmp_path):
  # In include-mode, the default goal (__main__) still runs (count guard preserved it).
  r = cmk(makefile=_wrapper(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr
  assert "hosted partition is live" in (r.stdout + r.stderr)


# --- tux.require ported into the hosted region (identity port) ---------------
# tux.require/tux.purge were moved from pure-make core into `define __hosted__`.
# They need docker to actually RUN; here we assert (no docker) they are BOUND as
# targets from a plain include, and that the region lowers cleanly.


def _bare_include(tmp_path):
  (tmp_path / ".cmk").mkdir(
    exist_ok=True
  )  # keep the hosted cache under tmp_path
  mk = tmp_path / "Makefile"
  mk.write_text("include %s\n" % COMPOSE_MK)
  return mk


def test_tux_require_bound_from_vanilla_make(cmk, tmp_path):
  # Dry-run resolves the hosted target (no "No rule"): proves the cache bound it.
  r = cmk(
    "--dry-run", "tux.require", makefile=_bare_include(tmp_path), cwd=tmp_path
  )
  assert r.ok, r.stderr
  assert "No rule to make target" not in (r.stdout + r.stderr), r.stderr
  assert "TUI containers are ready" in (r.stdout + r.stderr), (
    "recipe not present in dry-run"
  )


def test_tux_require_dependent_resolves(cmk, tmp_path):
  # A dependent (tux.shell: tux.require) must still resolve the prereq from the cache.
  r = cmk(
    "--dry-run", "tux.shell", makefile=_bare_include(tmp_path), cwd=tmp_path
  )
  assert r.ok, r.stderr
  assert "No rule to make target" not in (r.stdout + r.stderr), r.stderr


def test_tux_purge_bound_from_vanilla_make(cmk, tmp_path):
  r = cmk(
    "--dry-run", "tux.purge", makefile=_bare_include(tmp_path), cwd=tmp_path
  )
  assert r.ok, r.stderr
  assert "No rule to make target" not in (r.stdout + r.stderr), r.stderr


# --- cache-dir writability edges (global/pip install) ------------------------
# HOSTED_CACHE_DIR reuses CMK_MODULES_DIR only when it already exists AND is writable
# (a real project ./.cmk); else the always-writable user XDG cache.  This covers the
# `cmk` global install (CMK_MODULES_DIR -> READ-ONLY bundled plugins share) and avoids
# littering a fresh cwd's ./.cmk in global tool-mode.


def _plain_makefile(tmp_path):
  mk = tmp_path / "Makefile"  # NOTE: no pre-created ./.cmk here
  mk.write_text("include %s\n__main__: hosted.selftest\n" % COMPOSE_MK)
  return mk


def test_readonly_modules_dir_falls_back_to_xdg(cmk, tmp_path):
  ro = tmp_path / "ro-mods"
  ro.mkdir()
  ro.chmod(0o555)
  xdg = tmp_path / "xdg"
  try:
    r = cmk(
      "hosted.selftest",
      makefile=_plain_makefile(tmp_path),
      cwd=tmp_path,
      env={"CMK_MODULES_DIR": str(ro), "XDG_CACHE_HOME": str(xdg)},
    )
    assert r.ok, r.stderr  # must NOT hard-fail on the read-only dir
    assert "hosted partition is live" in (r.stdout + r.stderr), r.stderr
    assert list((xdg / "compose.mk").glob(".tmp.hosted.*.mk")), (
      "cache should fall back to XDG"
    )
    assert not list(ro.glob(".tmp.hosted.*")), (
      "nothing written to the read-only dir"
    )
  finally:
    ro.chmod(0o755)


def test_fresh_cwd_no_dotcmk_litter(cmk, tmp_path):
  # A plain `include compose.mk` in a dir with NO ./.cmk must not create one just to
  # hold the hosted cache (global tool-mode hygiene); the cache goes to XDG instead.
  xdg = tmp_path / "xdg"
  r = cmk(
    "hosted.selftest",
    makefile=_plain_makefile(tmp_path),
    cwd=tmp_path,
    env={"XDG_CACHE_HOME": str(xdg)},
  )
  assert r.ok, r.stderr
  assert not (tmp_path / ".cmk").exists(), (
    "must not litter ./.cmk in a fresh cwd"
  )
  assert list((xdg / "compose.mk").glob(".tmp.hosted.*.mk")), (
    "cache should be in XDG"
  )


# --- target enumeration: what each surface can see ---------------------------
# Per-surface coverage and the scanner fix it implies: scratch/help-enumeration-surfaces.md

# Witnesses, one per quadrant of (hosted | seed) x (parametric | literal).
_HOSTED_PARAMETRIC = ["flux.retry", "flux.pool"]
_HOSTED_LITERAL = ["hosted.selftest", "mk.stat", "io.echo"]
_SEED_PARAMETRIC = ["mk.help.target", "docker.image.run"]
_SEED_LITERAL = ["flux.ok"]
_ALL_WITNESSES = (
  _HOSTED_PARAMETRIC + _HOSTED_LITERAL + _SEED_PARAMETRIC + _SEED_LITERAL
)


def _bases(names):
  return {n.rstrip("/%").rstrip("/") for n in names}


def _help_names(cmk):
  r = cmk("help", env={"CMK_DISABLE_HOOKS": "1"})
  assert r.ok, r.stderr
  return _bases(_ANSI.sub("", r.stdout).split())


def _mk_targets_names(cmk):
  r = cmk("mk.targets", env={"path": str(COMPOSE_MK)})
  assert r.ok, r.stderr
  return _bases(_ANSI.sub("", r.stdout).split())


def test_hosted_parametric_targets_resolve_at_runtime(cmk):
  """The hosted targets the two surfaces disagree about are real, callable rules."""
  for target in _HOSTED_PARAMETRIC:
    r = cmk("-n", "%s/flux.ok" % target)
    assert "No rule to make target" not in (r.stdout + r.stderr), target


def test_help_lists_every_quadrant(cmk):
  """`help` spans both database sections, so no quadrant is missing from it."""
  listed = _help_names(cmk)
  missing = set(_ALL_WITNESSES) - listed
  assert not missing, sorted(missing)


def test_mk_targets_lists_the_seed(cmk):
  """The half of the scanner that works: seed targets, parametric ones included."""
  listed = _mk_targets_names(cmk)
  missing = set(_SEED_PARAMETRIC + _SEED_LITERAL) - listed
  assert not missing, sorted(missing)


@pytest.mark.xfail(
  strict=True,
  reason="`.awk.completion.scan` enters `define __hosted__` but its recipe-line guard "
  "then drops every indented line, and the partition is indented, so `mk.targets`, "
  "`help.local`, and `cmk cli targets` all report the seed only",
)
def test_mk_targets_lists_the_hosted_partition(cmk):
  """Desired state: the scanner reports targets authored in `__hosted__` too.

  Both hosted quadrants are asserted together because they fail for one reason: the
  literals sit at the partition's top level, the parametric ones inside exploded
  sub-modules, and the guard discards both.  Stripping a single indent level would
  turn only the literal half green.
  """
  listed = _mk_targets_names(cmk)
  missing = set(_HOSTED_LITERAL + _HOSTED_PARAMETRIC) - listed
  assert not missing, sorted(missing)
