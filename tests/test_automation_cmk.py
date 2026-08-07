"""Tests for the ``lint.self`` framework self-audit in ``.automation.cmk``.

``lint.self`` audits compose.mk core itself and was relocated out of core (it is maintainer
dev-tooling, not runtime framework). It has two parts:

  lint.self.collisions   macro/target name twins + their smart-route safety class; fails only on an
                         arg-dropping trampoline over a parametric target.
  lint.self.phase        the compiler's ``.awk.*`` phase markers; fails on a missing/inconsistent
                         marker or a broken seed-quarantine reference.

Because the targets live in the ``.automation.cmk`` module, each test loads them via a throwaway
wrapper that includes core plus the module (cwd=REPO so both paths resolve).
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.plugin

REPO = Path(__file__).resolve().parent.parent


def _run(cmk, target):
  wrapper = REPO / ".tmp.automation.probe.mk"
  wrapper.write_text(
    "include compose.mk\n$(call include.plugins, prefix=. .automation.cmk)\n"
  )
  try:
    return cmk(target, makefile=str(wrapper), cwd=REPO, timeout=60)
  finally:
    wrapper.unlink(missing_ok=True)


def test_lint_self_collisions_passes(cmk):
  r = _run(cmk, "lint.self.collisions")
  assert r.ok, r.stdout + r.stderr
  assert "macro/target twins" in r.stderr


def test_lint_self_phase_passes(cmk):
  # Guards the pin_scan drift this module fixed: the audit must recognize the current
  # lang.awk.export/stage.frag registration idiom and report zero failures.
  r = _run(cmk, "lint.self.phase")
  assert r.ok, r.stdout + r.stderr
  assert "0 failure(s)" in (r.stdout + r.stderr)
