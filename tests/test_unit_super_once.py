"""Unit tests for `m5.memoize!` and `log.warn.once` (`mk.super.once` = alias).

`m5.memoize! <key>` is a run-scoped once-guard: true the FIRST time this run for a
key, false after -- keyed on the supervisor pid (`MAKE_SUPER`, else this make's
`$$PPID`) baked at MAKE level, since `$(shell)` cannot see the exported var.  The
marker is `.tmp.mk.super.<pid>.once.<key>` (reapable via `mk.clean`).  It is the
run-scoped `!` sibling of the per-process value-cache `m5.memoize`; `mk.super.once`
is now a deprecated alias.  `log.warn.once <key> <msg>` chains that guard to
`log.warn`, so a fallback notice (jq/jb/glow off PATH) fires at most once per run.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrapper(tmp_path, recipe, name="so.mk"):
  w = tmp_path / name
  w.write_text(f"include {COMPOSE_MK}\nprobe:;{recipe}\n")
  return str(w)


def test_warn_once_single_fire_per_run(cmk, tmp_path):
  # log.warn.once chains to log.warn (glyph/color/quiet-gated), fired once/run.
  mk = _wrapper(
    tmp_path,
    "@$(call log.warn.once,tk,FALLBACKMSG7) ; "
    "$(call log.warn.once,tk,FALLBACKMSG7) ; echo done",
  )
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "done"
  assert r.stderr.count("FALLBACKMSG7") == 1, r.stderr


def test_super_once_marker_is_run_scoped_not_cwd(cmk, tmp_path):
  # Regression: `$(shell)` can't see the exported MAKE_SUPER, so mk.super.once
  # bakes the run key at MAKE level -> the marker is `.tmp.mk.super.*.once.*`
  # (reapable + run-scoped), never an unprefixed `.once.*` dropped in cwd.
  mk = _wrapper(tmp_path, "@$(call log.warn.once,zkey,X) ; true")
  r = cmk("probe", makefile=mk, cwd=tmp_path)
  assert r.ok, r.stderr
  assert not list(tmp_path.glob(".once.zkey")), "unprefixed cwd marker leaked"
  assert list(
    tmp_path.glob(".tmp.mk.super.*.once.zkey")
  ), "no run-scoped .tmp.mk.super.*.once.zkey marker created"


def test_memoize_bang_guard_true_then_false(cmk, tmp_path):
  # m5.memoize! itself: succeeds (runs the branch) the first time, fails after.
  mk = _wrapper(
    tmp_path,
    "@$(call m5.memoize!,gk) && echo FIRST || echo skip1 ; "
    "$(call m5.memoize!,gk) && echo second || echo SKIP2",
  )
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.split() == ["FIRST", "SKIP2"]


def test_mk_super_once_alias_still_works(cmk, tmp_path):
  # back-compat: the deprecated mk.super.once alias behaves identically.
  mk = _wrapper(
    tmp_path,
    "@$(call mk.super.once,ak) && echo FIRST || echo skip1 ; "
    "$(call mk.super.once,ak) && echo second || echo SKIP2",
  )
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.split() == ["FIRST", "SKIP2"]
