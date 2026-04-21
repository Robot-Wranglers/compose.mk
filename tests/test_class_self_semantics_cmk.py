"""Class-compiled `self`: declaration + read semantics, asserted E2E.

Pins what the golden demo (`demos/cmk/metaprogramming.cmk`, target `demo.self`)
models: a class body uses bare `self.x` for declarations AND reads (the `${self}`
lowering is an implementation detail, kept out of the demo).  Verified here:

  * a CLASSVAR (`classvars='v=..'` kwarg) reaches `<Class>.v`, `<inst>.v`, and a
    body `self.v` read;
  * an INSTANCE-VAR (`self.v = ..`) and a bare `v = ..` reach `<inst>.v` and a
    body `self.v` read, but NOT `<Class>.v` -- bare-assign is observably an
    instance default, identical to `self.v =`, NOT a class-level classvar;
  * a TARGET (`self.t:`) is declared with bare self and invoked from outside via
    `<inst>.t()` (as the demo does `gizmo.show()`).  NOTE: bare `self.t()` from a
    SIBLING recipe self-desugars to a read (`$(<inst>.t)()`), so a within-body
    target invocation needs the `${self}.t()` braces-callform instead.

`self.x` compiles the same however it lowers -- these assert the behavior, not the
lowering.  Docker-free (make/bash only).
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("metaprogramming.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _probe(tmp_path):
  # One class with a kwarg classvar (cv), a self. instance-var (iv), a bare
  # instance default (bare), a method that reads all three via bare self.x, and a
  # target invoked from a sibling target via the self.t() callform.
  src = (
    "from cmk import class\n"
    "import log\n"
    "class W(classvars='cv=CV')[|\n"
    "  self.iv = IV\n"
    "  bare = BARE\n"
    "  self.desc = cv:self.cv iv:self.iv bare:self.bare\n"
    "  self.tgt:; cmk.log(TGT-RAN ${sep} self.desc)\n"
    "|]\n"
    "w <- W.new()\n"
    "report:\n"
    "\t@printf 'CV=[cls=%s inst=%s] IV=[cls=%s inst=%s] BARE=[cls=%s inst=%s] DESC=[%s]\\n' "
    "'$(W.cv)' '${w.cv}' "
    "'$(origin W.iv)' '${w.iv}' "
    "'$(origin W.bare)' '${w.bare}' "
    "'${w.desc}'\n"
    "\tw.tgt()\n"
    "__main__: report\n"
  )
  f = tmp_path / "self.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "report"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True, text=True,
    errors="replace", timeout=120,
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  line = next((l for l in out.splitlines() if "CV=[" in l), None)
  assert line, f"no probe line: {out[-1500:]}"
  fields = dict(re.findall(r"(\w+)=\[([^\]]*)\]", line))
  return fields, out


def test_classvar_kwarg_reaches_class_instance_and_self(tmp_path):
  # A `classvars=` classvar is on the CLASS, every instance, and a body self. read.
  fs, out = _probe(tmp_path)
  assert fs["CV"] == "cls=CV inst=CV", out


def test_instance_var_reaches_instance_and_self_not_class(tmp_path):
  # `self.iv = ..` reaches the instance (and a self. read) but not the class.
  fs, out = _probe(tmp_path)
  assert fs["IV"] == "cls=undefined inst=IV", out


def test_bare_assign_is_instance_default_not_a_classvar(tmp_path):
  # A bare `bare = ..` is IDENTICAL to `self.bare = ..`: instance + self, NOT class.
  fs, out = _probe(tmp_path)
  assert fs["BARE"] == "cls=undefined inst=BARE", out


def test_self_reads_compile_in_a_method(tmp_path):
  # A member value reads a classvar, an instance-var, and a bare default via bare self.x.
  fs, out = _probe(tmp_path)
  assert fs["DESC"] == "cv:CV iv:IV bare:BARE", out


def test_target_declared_with_self_and_invoked_externally(tmp_path):
  # `self.tgt:` (declared with bare self) is invoked from outside via `w.tgt()`,
  # matching the demo's `gizmo.show()`; the target's own recipe reads via self.
  fs, out = _probe(tmp_path)
  assert "TGT-RAN" in out, out
  assert "cv:CV iv:IV bare:BARE" in out, out
