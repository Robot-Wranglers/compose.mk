"""Characterization of the three metaclass-variable forms and their access/inheritance.

This suite PINS CURRENT BEHAVIOUR (not the desired end-state) for the spectrum of
ways to attach a member <name> to a kind.  The name is a GENERIC identifier -- the
dunder convention (e.g. `__lang__`) is incidental; `color`/`base` work identically,
so these tests use plain names on purpose.  SSOT semantics; see TODO-classvars.md.
Three forms, greppable by test-name token:

  * CLASSVAR  (`test_classvar_*`)   -- `KIND(classvars='<name>=v')`
        class-scoped: stored on the CLASS, read-through onto each instance.
  * PROPERTY  (`test_property_*`)   -- body `<name> = v` (bare, no `${self}.` prefix)
        instance-scoped BUT registered: stored on the INSTANCE, name recorded in the
        instance's `.__classvars__` (introspectable).  The bare body assignment is the
        blessed form; the cook lowers it to the internal
        `$(call lang.seed.grow!,lang.class.classvar,${self},<name>=v)`.  The `${self}.`
        prefix is exactly what demotes a property to an unregistered RAW ATTR (below).
  * RAW ATTR  (`test_raw_attr_*`)   -- body `${self}.<name> = v`
        instance-scoped, UNregistered: a bare member, invisible to reflection.

Access axes: internal `self.<name>`, external `<inst>.<name>`, external
`<Class>.<name>`; plus the `.__classvars__` registry and inheritance (the registry
member stays dunder; the classvar names it holds are arbitrary).  Docker-free.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "cvsem.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


# ─── CLASSVAR: class-scoped, read-through ────────────────────────────────────

def test_classvar_access_self_instance_and_class(tmp_path):
  # a classvar resolves on ALL THREE surfaces: internal self.X, external
  # <inst>.X, and external <Class>.X.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='color=teal')[|\n"
    "  ${self}.show:; @printf 'IN=[%s]' '$(self.color)'\n"
    "|]\n"
    "cmk.widget(w)\n"
    "probe:; @printf ' EXTi=[%s] EXTc=[%s]' '$(w.color)' '$(widget.color)'\n"
    "__main__: w.show probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "IN=[teal] EXTi=[teal] EXTc=[teal]" in out, out


def test_classvar_registered_on_class_not_instance(tmp_path):
  # the name is recorded in <Class>.__classvars__, NOT on the instance.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget(classvars='color=teal')[| |]\n"
    "cmk.widget(w)\n"
    "probe:; @printf 'cls=[%s] inst=[%s]' '$(widget.__classvars__)' '$(w.__classvars__)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "cls=[color] inst=[]" in out, out


def test_classvar_inherits_via_ifaces_to_instances(tmp_path):
  # a classvar declared on a protocol flows to a conformer's INSTANCES via ifaces=.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Painted(dunder=__p__ classvars='color=blue')(| |)\n"
    "class widget(ifaces=Painted)[| |]\n"
    "cmk.widget(w)\n"
    "probe:; @printf 'inst=[%s]' '$(w.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[blue]" in out, out


def test_classvar_not_inherited_via_bases_and_subclass_class_empty(tmp_path):
  # CURRENT GAP (see TODO-classvars.md): classvar inheritance flows ONLY through a
  # direct ifaces= edge.  (1) bases= does NOT carry the value to instances;
  # (2) the subclass CLASS itself never carries an inherited classvar (only the
  # declaring class does); (3) a bases= hop severs even an iface-sourced classvar.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Painted(dunder=__p__ classvars='color=blue')(| |)\n"
    "class Base(classvars='tone=warm')[| |]\n"
    "class ViaBase(bases=Base)[| |]\n"          # inherit a classvar via bases=
    "class ViaIface(ifaces=Painted)[| |]\n"     # inherit via ifaces=
    "class Deep(bases=ViaIface)[| |]\n"         # one bases= hop below an iface source
    "cmk.ViaBase(vb)\n"
    "cmk.Deep(dp)\n"
    "probe:; @printf 'basesInst=[%s] subCls=[%s] deepInst=[%s]' "
    "'$(vb.tone)' '$(ViaIface.color)' '$(dp.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "basesInst=[] subCls=[] deepInst=[]" in out, out


def test_classvar_override_wins_on_instance_and_class(tmp_path):
  # a conformer that redeclares the classvar overrides the inherited value, and
  # (because it now stores its own) the override is visible on the subclass CLASS too.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Painted(dunder=__p__ classvars='color=blue')(| |)\n"
    "class widget(ifaces=Painted classvars='color=own')[| |]\n"
    "cmk.widget(w)\n"
    "probe:; @printf 'inst=[%s] cls=[%s]' '$(w.color)' '$(widget.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[own] cls=[own]" in out, out


# ─── PROPERTY: instance-scoped, registered ───────────────────────────────────

def test_property_access_self_and_instance_only(tmp_path):
  # a body-declared property resolves internally (self.X) and externally on the
  # INSTANCE, but NOT on the class -- it is instance-scoped.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  color = blue\n"
    "  ${self}.show:; @printf 'IN=[%s]' '$(self.color)'\n"
    "|]\n"
    "cmk.widget(w)\n"
    "probe:; @printf ' EXTi=[%s] EXTc=[%s]' '$(w.color)' '$(widget.color)'\n"
    "__main__: w.show probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "IN=[blue] EXTi=[blue] EXTc=[]" in out, out


def test_property_registered_on_instance_not_class(tmp_path):
  # unlike a classvar, the name is recorded in the INSTANCE's __classvars__
  # (introspectable per-instance), not on the class.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  color = blue\n"
    "|]\n"
    "cmk.widget(w)\n"
    "probe:; @printf 'inst=[%s] cls=[%s]' '$(w.__classvars__)' '$(widget.__classvars__)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[color] cls=[]" in out, out


def test_property_inherits_via_bases_body_rerun(tmp_path):
  # a property inherits through bases= -- because the body is a mixin that RE-RUNS
  # per instance, so the value re-materialises on each subclass instance.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  color = blue\n"
    "|]\n"
    "class sub(bases=widget)[| |]\n"
    "cmk.sub(s)\n"
    "probe:; @printf 'inst=[%s]' '$(s.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[blue]" in out, out


def test_property_bare_assignment_equivalent_to_raw_grow(tmp_path):
  # the blessed bare `name = value` body assignment lowers to the internal
  # `$(call lang.seed.grow!,lang.class.classvar,${self},name=value)` -- same
  # registration, same instance-scoped read-through, name in the instance registry.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class blessed[| color = blue |]\n"
    "class raw[| $(call lang.seed.grow!,lang.class.classvar,${self},color=blue) |]\n"
    "cmk.blessed(b)\n"
    "cmk.raw(w)\n"
    "probe:; @printf 'B=[%s/%s] R=[%s/%s]' "
    "'$(b.color)' '$(b.__classvars__)' '$(w.color)' '$(w.__classvars__)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "B=[blue/color] R=[blue/color]" in out, out


# ─── RAW ATTR: instance-scoped, unregistered ─────────────────────────────────

def test_raw_attr_access_self_and_instance_only(tmp_path):
  # a plain body assignment resolves internally and on the instance, but not the
  # class -- and registers nothing.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  ${self}.color = blue\n"
    "  ${self}.show:; @printf 'IN=[%s]' '$(self.color)'\n"
    "|]\n"
    "cmk.widget(w)\n"
    "probe:; @printf ' EXTi=[%s] EXTc=[%s]' '$(w.color)' '$(widget.color)'\n"
    "__main__: w.show probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "IN=[blue] EXTi=[blue] EXTc=[]" in out, out


def test_raw_attr_not_registered_anywhere(tmp_path):
  # a raw attribute is invisible to reflection: no __classvars__ entry on the
  # instance OR the class.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  ${self}.color = blue\n"
    "|]\n"
    "cmk.widget(w)\n"
    "probe:; @printf 'inst=[%s] cls=[%s]' '$(w.__classvars__)' '$(widget.__classvars__)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[] cls=[]" in out, out


def test_raw_attr_inherits_via_bases_body_rerun(tmp_path):
  # like a property, a raw attribute inherits through bases= via body re-run.
  r, out = _run_cmk(
    "from cmk import class\n"
    "class widget[|\n"
    "  ${self}.color = blue\n"
    "|]\n"
    "class sub(bases=widget)[| |]\n"
    "cmk.sub(s)\n"
    "probe:; @printf 'inst=[%s]' '$(s.color)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[blue]" in out, out
