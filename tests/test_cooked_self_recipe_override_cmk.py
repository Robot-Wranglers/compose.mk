"""A cooked-body `self.X:` recipe override is deduped by shadowclean -- no warning.

shadowclean silently dedups a subclass's recipe-target override against a base's, by
scanning the class-body manifest for recipe heads AT CLASS-DECL.  It now recognizes
BOTH `${self}.X:` and the cooked `self.X:` form (which the self-desugar rewrites to
`${self}.` only at STAMP) -- so a cooked `self.fmt:` overriding code.compiled's
`${self}.fmt:` is deduped, with no `overriding recipe` warning (regression for the
former cook-vs-stamp gap; see lang.class.target.manifest).  Docker-free.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "cso.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


_SRC_COOKED = (
  "from cmk import class\n"
  "cmk.class Base(| ${self}.act:; @echo base |)\n"
  "cmk.class Sub(bases=Base)[| self.act:; @echo sub |]\n"
  "Sub s(| |)\n"
  "__main__: s.act\n"
)
_SRC_EXPLICIT = _SRC_COOKED.replace("self.act:;", "${self}.act:;")


def test_cooked_self_recipe_override_deduped(tmp_path):
  # a cooked `self.act:` override of a base recipe target is recognized by
  # shadowclean -> deduped, no 'overriding recipe' warning, and the override wins.
  r, out = _run_cmk(_SRC_COOKED, tmp_path)
  assert r.returncode == 0, out
  assert "overriding recipe" not in out, out
  assert "sub" in out, out                       # the override wins


def test_explicit_self_recipe_override_deduped(tmp_path):
  # `${self}.act:` (explicit head) is deduped too -- both spellings are clean.
  r, out = _run_cmk(_SRC_EXPLICIT, tmp_path)
  assert r.returncode == 0, out
  assert "overriding recipe" not in out, out
