"""The `self.<target>:` idiom -- bare self is interchangeable with `${self}.`.

A class body declares a recipe target keyed on the instance.  The idiomatic form
is bare `self.tgt:` (the `${self}` lowering is an implementation detail).  This
holds for a NULLARY target, an OVERRIDDEN target (subclass redefines it), and a
PARAMETRIC target -- each asserted below alongside its equivalent `${self}.tgt:`
control, so any divergence is provably a surface-form bug, not the scenario:

  Gap A -- OVERRIDE dedup: a subclass overriding an inherited `self.tgt:` must emit
  ONE recipe (no `overriding recipe`).  Fixed by teaching `.awk.self.strip` (the
  shadowed-block remover) the bare `self.` header, not just literal `${self}`.

  Gap B -- PARAMETRIC target: `self.tgt/%:` must lower to a target header, not a
  read.  Fixed by lowering a leading self-target header (`lang.class.comp.self.hdr`)
  before tokenization, so the `/%` no longer routes `self.tgt` to a read.

Docker-free (make/bash only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, src):
  f = tmp_path / "sti.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "report"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True, text=True,
    errors="replace", timeout=120,
  )
  return p, p.stdout + p.stderr


# -- boundary (PASSING today): nullary, non-overridden self target lowers --

def test_nullary_self_target_lowers(tmp_path):
  # A standalone (non-overridden) nullary `self.tgt:` works -- the demo showcase form.
  p, out = _run(
    tmp_path,
    "from cmk import class\nimport log\n"
    "class Widget[|\n"
    "  self.show:\n"
    "    cmk.log(SHOW-RAN)\n"
    "|]\n"
    "w <- Widget.new()\n"
    "report:\n\tw.show()\n"
    "__main__: report\n",
  )
  assert p.returncode == 0, out
  assert "SHOW-RAN" in out, out
  assert "overriding recipe" not in out, out


def test_inline_recipe_self_read_is_a_read_not_the_header(tmp_path):
  # An INLINE `self.tgt:; recipe` must still READ a self.x in its body (not rewrite it
  # to the instance name).  Regression guard: the block-header lowering (self.hdr) must
  # NOT fire on a `;` inline line, or `self.x` in the recipe becomes literal `<inst>.x`.
  p, out = _run(
    tmp_path,
    "from cmk import class\nimport log\n"
    "class W[|\n"
    "  x = XVAL\n"
    "  self.tgt:; cmk.log(READ ${sep} self.x)\n"
    "|]\n"
    "w <- W.new()\n"
    "report:\n\tw.tgt()\n"
    "__main__: report\n",
  )
  assert p.returncode == 0, out
  assert "READ" in out and "XVAL" in out, out   # the value, not the literal `w.x`
  assert "w.x" not in out, out


# -- Gap A: override dedup with self. (control with ${self} passes) --

def _override_src(kind):
  # kind is 'self.' or '${self}.' -- the ONLY difference between control and target.
  return (
    "from cmk import class\nimport log\n"
    "class Base[|\n"
    f"  {kind}act:\n"
    "    cmk.log(BASE-ACT)\n"
    "|]\n"
    "class Sub(bases=Base)[|\n"
    f"  {kind}act:\n"
    "    cmk.log(SUB-ACT)\n"
    "|]\n"
    "s <- Sub.new()\n"
    "report:\n\ts.act()\n"
    "__main__: report\n"
  )


def test_override_dedup_control_braces_is_clean(tmp_path):
  # CONTROL: the ${self}. form dedups the shadowed base recipe -- no warning.
  p, out = _run(tmp_path, _override_src("${self}."))
  assert p.returncode == 0, out
  assert "SUB-ACT" in out, out                  # override wins
  assert "overriding recipe" not in out, out


def test_override_dedup_self_form_is_clean(tmp_path):
  # TARGET: same scenario in the idiomatic bare-self form should ALSO be clean.
  p, out = _run(tmp_path, _override_src("self."))
  assert p.returncode == 0, out
  assert "SUB-ACT" in out, out
  assert "overriding recipe" not in out, out


# -- Gap B: parametric target with self. (control with ${self} passes) --

def _param_src(kind):
  return (
    "from cmk import class\nimport log\n"
    "class Thing[|\n"
    f"  {kind}emit/%:\n"
    "    cmk.log(PARAM-RAN ${sep} $*)\n"
    "|]\n"
    "t <- Thing.new()\n"
    "report:\n\tt.emit(hello)\n"
    "__main__: report\n"
  )


def test_parametric_target_control_braces_lowers(tmp_path):
  # CONTROL: the ${self}. parametric target lowers and is invokable.
  p, out = _run(tmp_path, _param_src("${self}."))
  assert p.returncode == 0, out
  assert "PARAM-RAN" in out and "hello" in out, out


def test_parametric_target_self_form_lowers(tmp_path):
  # TARGET: the idiomatic bare-self parametric target should lower the same way.
  p, out = _run(tmp_path, _param_src("self."))
  assert p.returncode == 0, out
  assert "PARAM-RAN" in out and "hello" in out, out
