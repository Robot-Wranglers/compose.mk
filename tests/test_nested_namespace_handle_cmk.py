"""Nested `namespace`/`module` handle promotion (SPIKE-banana-asm.md, exp 4).

A `namespace` (and `module`, which is-a namespace) threads `__name__` and
qualifies member LHS with the fully-qualified path.  When nested
(`namespace outer[| namespace inner[| leaf=.. |] |]`), the CURRENT behavior is
HALF-PROMOTED:

  * leaf members qualify by full path (`outer.inner.leaf`), and the inner's own
    `.__name__` composes to `outer.inner`  -- pinned by the reality test;
  * the inner OBJECT handle `outer.inner` is now bound and registered in
    `outer.__all__` when nested  -- pinned by the promotion test.  (The ctor
    stamps these under a `$(if $(__name__),..)` guard, so top-level namespaces
    are unaffected.)

Previously half-promoted: the handle was undefined and `outer.__all__` empty.
The only nested-namespace user, demos/cmk/ambients-open.cmk, reaches its leaves
fully-qualified (`tier1.tier2.foo` / `.report` / `.__name__`) and is unaffected.
See the ctor at compose.mk:4410-4431.

Docker-free (make/bash only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("ambients-open.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _probe(tmp_path, kw):
  # A two-level nest with a leaf at the inner level, then a report recipe that
  # introspects the outcome with parse-safe make functions (a `this.log(..)`
  # callform would mangle the `$(origin ..)` spaces, so use raw `@printf`).
  src = (
    f"from cmk import {kw}\n"
    f"{kw} outer[|\n"
    f"  {kw} inner[|\n"
    f"    leaf = DEEP\n"
    f"  |]\n"
    f"|]\n"
    f"report:\n"
    f"\t@printf 'HANDLE=%s INALL=%s LEAK=%s LEAF=%s NAME=%s\\n' \\\n"
    f"\t  '$(if $(filter-out undefined,$(origin outer.inner)),y,n)' \\\n"
    f"\t  '$(if $(filter inner outer.inner,$(outer.__all__)),y,n)' \\\n"
    f"\t  '$(if $(filter-out undefined,$(origin inner)),y,n)' \\\n"
    f"\t  '$(if $(filter-out undefined,$(origin outer.inner.leaf)),y,n)' \\\n"
    f"\t  '$(outer.inner.__name__)'\n"
    f"__main__: report\n"
  )
  f = tmp_path / "nns.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "report"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  fields = {}
  for line in out.splitlines():
    if line.startswith("HANDLE="):
      for kv in line.split():
        k, _, v = kv.partition("=")
        fields[k] = v
      break
  assert fields, f"no probe line in output: {out[-1500:]}"
  return fields, out


@pytest.mark.parametrize("kw", ["namespace", "module"])
def test_nested_leaf_qualifies_reality(tmp_path, kw):
  # KEPT behavior: __name__ threading qualifies leaf members by full path and
  # composes the inner's fq name.  This is what ambients-open.cmk relies on.
  f, out = _probe(tmp_path, kw)
  assert f["LEAF"] == "y", out  # outer.inner.leaf is defined (qualified)
  assert f["NAME"] == "outer.inner", out  # inner.__name__ composed the path


@pytest.mark.parametrize("kw", ["namespace", "module"])
def test_nested_handle_promoted(tmp_path, kw):
  # Closing half-promotion binds the inner OBJECT handle `outer.inner` and
  # registers it in `outer.__all__` (so nesting yields a real, reachable child,
  # not just qualified leaves).  The namespace ctor stamps both when nested.
  f, out = _probe(tmp_path, kw)
  assert f["HANDLE"] == "y", out  # outer.inner is a defined handle
  assert f["INALL"] == "y", out  # outer.__all__ lists the child
