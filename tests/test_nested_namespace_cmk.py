"""What nesting does to a namespace's own bookkeeping: the child handle, and the member manifest.

A `namespace` (and `module`, which is-a namespace) threads `__name__` and qualifies member names
with the fully-qualified path.  Nested, it also binds the child handle (`outer.inner`) and lists
the child in `outer.__all__`; the ctor stamps both under a name guard, so top-level namespaces are
unaffected.  The nested-namespace demo, demos/cmk/ambients-open.cmk, reaches its leaves fully
qualified and relies on the qualification half.

The manifest cases reach past the Directory protocol: core parents an ambient's members by walking
`__all__`, so a member missing from the manifest never joins the containment chain either.

Docker-free (make and bash only).
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


def _manifest(tmp_path):
  """Shapes whose manifest a nested body used to corrupt.

  A plain member beside a nested namespace, two sibling namespaces, and a three-level nest.
  """
  src = (
    "from cmk import machine, namespace\n"
    "namespace subj(|\n"
    "  machine a(entrypoint=bash)(| |)\n"
    "  namespace first(|\n"
    "    machine f(entrypoint=bash)(| |)\n"
    "  |)\n"
    "  namespace last(|\n"
    "    machine l(entrypoint=bash)(| |)\n"
    "  |)\n"
    "|)\n"
    "namespace d3(|\n"
    "  namespace mid(|\n"
    "    namespace inner(|\n"
    "      machine k(entrypoint=bash)(| |)\n"
    "    |)\n"
    "  |)\n"
    "|)\n"
    "report:\n"
    "\t@printf 'SUBJ=[%s] FIRST=[%s] LAST=[%s] MID=[%s] AP=[%s]\\n' \\\n"
    "\t  '$(subj.__all__)' '$(subj.first.__all__)' '$(subj.last.__all__)' \\\n"
    "\t  '$(d3.mid.__all__)' '$(subj.a.__ambient_parent__)'\n"
    "__main__: report\n"
  )
  f = tmp_path / "manifest.cmk"
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
  assert p.returncode == 0, out[-1500:]
  return out


def test_member_survives_a_nested_namespace_sibling(tmp_path):
  """A plain member declared beside a nested namespace stays a member, and gets parented.

  The manifest is collected after the body is read, and a nested body left the name pointing at
  itself, so the enclosing namespace collected nothing of its own.
  """
  out = _manifest(tmp_path)
  assert "SUBJ=[a first last]" in out, out[-1500:]
  assert "AP=[subj]" in out, out[-1500:]


def test_sibling_namespaces_keep_their_own_manifests(tmp_path):
  """The enclosing collection used to land on whichever sibling was declared last."""
  out = _manifest(tmp_path)
  assert "FIRST=[f] LAST=[l]" in out, out[-1500:]


def test_a_middle_namespace_does_not_leak_its_own_attributes(tmp_path):
  """Three deep, the middle level also subtracted the wrong baseline, so its own attributes read as members."""
  out = _manifest(tmp_path)
  assert "MID=[inner]" in out, out[-1500:]


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
