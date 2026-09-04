"""Nested `module`/`namespace` docstrings + source-ordered `__children__`.

Pins the behavior the `demos/cmk/banana-asm.cmk` tree demo exercises, but
pointed at the built-in `module` kind (and `namespace`, which it is-a) rather
than a demo-local `lang.tree`.  `module` is `dsl.cmklang + cmk.namespace`
(compose.mk:4479), the same recipe `lang.tree` / `graal.group` re-derive, so
this is the core contract both demos lean on:

  * a COOKED banana body's leading `'''..'''` lifts to `<name>.__doc__` (this was
    silently `[]` before the always-lift fix -- cooked bodies never self-ran the
    in-body carrier);
  * a NESTED member's docstring qualifies to the full path (`Site.api.v2.__doc__`),
    not a global `v2.__doc__` -- the ns-qualifier prefixes the lifted define;
  * `__children__` lists direct members in SOURCE order, driven by a per-banana
    `__line__` position (NOT alphabetical: declared `web api db`, which sorts to
    `api db web`).

`__children__` is stamped by the `cmk.namespace` ctor (compose.mk:4458); `module`
inherits it.  Docker-free (make/bash only).
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.docstring, pytest.mark.module_system, pytest.mark.covers_demo("banana-asm.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _probe(tmp_path, kw):
  # A two-plus-level nest declared web -> api(-> v2) -> db, each carrying a
  # docstring, plus a top-level docstring; `report` introspects the outcome.
  src = (
    f"from cmk import {kw}\n"
    f"{kw} Site[|\n"
    f"  '''site root'''\n"
    f"  {kw} web[|\n"
    f"    '''web tier'''\n"
    f"    port = 8080\n"
    f"  |]\n"
    f"  {kw} api[|\n"
    f"    '''api tier'''\n"
    f"    {kw} v2[|\n"
    f"      '''api v2'''\n"
    f"      port = 8002\n"
    f"    |]\n"
    f"  |]\n"
    f"  {kw} db[|\n"
    f"    '''db tier'''\n"
    f"    port = 5432\n"
    f"  |]\n"
    f"|]\n"
    f"report:\n"
    f"\t@printf 'ROOTDOC=[%s] WEBDOC=[%s] V2DOC=[%s] CHILDREN=[%s] APIKIDS=[%s] WEBPORT=[%s]\\n' \\\n"
    f"\t  '$(Site.__doc__)' '$(Site.web.__doc__)' '$(Site.api.v2.__doc__)' \\\n"
    f"\t  '$(strip $(Site.__children__))' '$(strip $(Site.api.__children__))' '$(Site.web.port)'\n"
    f"__main__: report\n"
  )
  f = tmp_path / "tree.cmk"
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
  line = next((l for l in out.splitlines() if "ROOTDOC=[" in l), None)
  assert line, f"no probe line in output: {out[-1500:]}"
  fields = dict(re.findall(r"(\w+)=\[([^\]]*)\]", line))
  return fields, out


@pytest.mark.parametrize("kw", ["module", "namespace"])
def test_cooked_docstring_lifts(tmp_path, kw):
  # A cooked `[| .. |]` body's leading docstring lands on the instance's __doc__.
  f, out = _probe(tmp_path, kw)
  assert f["ROOTDOC"] == "site root", out


@pytest.mark.parametrize("kw", ["module", "namespace"])
def test_nested_docstring_qualifies(tmp_path, kw):
  # A nested member's docstring qualifies to its full dotted path, at any depth.
  f, out = _probe(tmp_path, kw)
  assert f["WEBDOC"] == "web tier", out  # depth 1
  assert f["V2DOC"] == "api v2", out  # depth 2


@pytest.mark.parametrize("kw", ["module", "namespace"])
def test_children_are_source_ordered(tmp_path, kw):
  # __children__ is direct members in SOURCE order, not sorted (sorted = "api db web").
  f, out = _probe(tmp_path, kw)
  assert f["CHILDREN"] == "web api db", out
  assert f["APIKIDS"] == "v2", out  # a nested container reports its own child


@pytest.mark.parametrize("kw", ["module", "namespace"])
def test_qualified_leaf_reachable(tmp_path, kw):
  # sanity: a leaf member is reachable by its qualified path.
  f, out = _probe(tmp_path, kw)
  assert f["WEBPORT"] == "8080", out


@pytest.mark.covers_demo("graal-interop.cmk")
def test_childtest_override_broadens_membership(tmp_path):
  # A kind overrides the default is-a membership test via `<class>.__childtest__`.
  # This is how `graal.group` counts its language fragments as children even though
  # they are NOT is-a the group.  Pinned docker-free (the graal demo needs docker to
  # RUN); here modules-in-a-box are counted by a `tag` attr the default test ignores.
  src = (
    "from cmk import class\n"
    "from cmk import module\n"
    "cmk.class box(bases=cmk.namespace)(||)\n"
    "box.__childtest__ = $(if $(filter-out undefined,$(origin $(strip ${1}).$(strip ${2}).tag)),1,)\n"
    "box B[|\n"
    "  module beta[| tag = 2 |]\n"
    "  module alpha[| tag = 1 |]\n"
    "  module gamma[| tag = 3 |]\n"
    "|]\n"
    "report:\n"
    "\t@printf 'CUSTOM=[%s] DEFAULT=[%s]\\n' '$(strip $(B.__children__))' '$(strip $(call lang.proto.tmpl.directory.childtest.default,B,beta))'\n"
    "__main__: report\n"
  )
  f = tmp_path / "childtest.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "report"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True, text=True,
    errors="replace", timeout=120,
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  line = next((l for l in out.splitlines() if "CUSTOM=[" in l), None)
  assert line, f"no probe line: {out[-1500:]}"
  fs = dict(re.findall(r"(\w+)=\[([^\]]*)\]", line))
  assert fs["CUSTOM"] == "beta alpha gamma", out  # override includes them, source order
  assert fs["DEFAULT"] == "", out  # default is-a test would have excluded them
