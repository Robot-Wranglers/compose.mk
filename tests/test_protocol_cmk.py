"""End-to-end for the `protocol` keyword (demos/cmk/protocol.cmk).

`protocol` is a first-class declaration keyword (beside `class` / `container`)
that mints an ABC / interface for a dunder -- cmk's take on Python's data model.
Each protocol names the members a carrier must expose (`abstract`); the structural
check `.provided_by` (Python's __subclasshook__) verifies conformance, with
`.register` for conformers the check can't see.

This proves the shipped surface end-to-end via the demo:
  * the data model lists all declared protocols (Documented/Registry/Named + a
    user-declared `Hashable`);
  * the Registry protocol structurally accepts BOTH __plugins__ and __modules__
    (one ABC, two real conformers, no registration);
  * Documented.provided_by / .get unify the __doc__ carrier;
  * explicit .register flips a non-conformer to a conformer.

Marked `unit` (fast, no docker).  Compile/attribute-level coverage is in
test_compiler_cmk.py-style checks; here we run the real program.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("protocol.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "protocol.cmk"

_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run(*targets, timeout=180):
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_demo_runs_clean():
  r, out = _run()
  assert r.returncode == 0, out


def test_data_model_lists_every_protocol():
  # `lang.proto.registry` accumulates each minted protocol, incl. the user-declared one.
  r, out = _run("demo.model")
  assert r.returncode == 0, out
  assert "Documented Registry Named Loggable Directory Program Openable Callable Templatable Materializable Feedable Runnable Ambient Language Hashable" in out
  # each protocol reports its contract (dunder / abstract members).
  assert "dunder=__doc__ abstract=__doc__" in out
  assert "members=has require" in out
  assert "dunder=__hash__ abstract=__hash__" in out  # the user-declared `hashable`


def test_registry_protocol_accepts_three_real_dunders():
  # the ABC win: one interface (`.has`/`.require`) structurally matches __plugins__,
  # __modules__ AND __ambients__ with no registration; a non-registry does not.
  r, out = _run("demo.structural")
  assert r.returncode == 0, out
  assert re.search(r"Registry\.provided_by/__plugins__ .*\b1\b", out), out
  assert re.search(r"Registry\.provided_by/__modules__ .*\b1\b", out), out
  assert re.search(r"Registry\.provided_by/__ambients__ .*\b1\b", out), out
  assert "not-a-registry = []" in out


def test_ambients_registry_has_require_roundtrip():
  # __ambients__ is a real registry carrier: `.require` declares a missing ambient
  # (the acquire), then `.has` detects it -- before empty, after the bare NAME (names-only:
  # config lives on the KIND instance, not the registry).  Proves the interface is
  # load-bearing, not just structurally present.
  r, out = _run("demo.structural")
  assert r.returncode == 0, out
  assert re.search(r"__ambients__\.has/demoamb .*before-require = \[\] after = demoamb\b", out), out


@pytest.mark.docstring
def test_docstring_provided_by_and_get():
  # structural check sees the `.__doc__` member; `.get` reads it back.
  r, out = _run("demo.docstring")
  assert r.returncode == 0, out
  assert re.search(r"provided_by/documented .*\b1\b", out), out
  assert "no-doc = []" in out
  assert "a hand-written module docstring" in out


@pytest.mark.docstring
def test_target_docstring_reflection():
  # the runtime `__target__` carrier: a recipe reflects its own `'''docstring'''`.
  r, out = _run("demo.docstring")
  assert r.returncode == 0, out
  assert "unify the __doc__ carrier" in out


def test_register_flips_a_non_conformer():
  # ABC.register: `plain` has no `.__doc__`, so structural check is empty; after
  # registration it conforms, and appears in `.registry`.
  r, out = _run("demo.register")
  assert r.returncode == 0, out
  assert "before-register" in out and "provided_by/plain = []" in out
  assert "after-register" in out and "provided_by/plain = [1]" in out
  assert "_cmk.target.doc plain" in out


def test_protocol_inheritance_unions_abstract():
  # `Sequence(Container)`: the derived protocol UNIONS its base's abstract members
  # (Container's `__contains__`) with its own (`__getitem__`) into one contract, and
  # publishes the reflection dunders `.__bases__` / `.__mro__` like any class.
  r, out = _run("demo.inherit")
  assert r.returncode == 0, out
  assert re.search(r"Sequence\.abstract .*__contains__ __getitem__", out), out
  assert re.search(r"Sequence\.__bases__ .* Container\b", out), out
  assert re.search(r"Sequence\.__mro__ .* Container Sequence\b", out), out


def test_protocol_inheritance_provided_by_is_transitive():
  # a conformer must expose the INHERITED member too: `seq.full` has both
  # __contains__ and __getitem__ (accepted); `seq.partial` lacks __contains__
  # (rejected) -- the union makes `.provided_by` demand the base's contract.
  r, out = _run("demo.inherit")
  assert r.returncode == 0, out
  assert re.search(r"provided_by/full .*has both = 1", out), out
  assert re.search(r"provided_by/partial .*missing __contains__ = \[\]", out), out


def test_issubclass_over_protocols():
  # issubclass reads `.__mro__`: Sequence IS-A Container (derived), but Container
  # is NOT a Sequence -- inheritance is directional, same as Python's issubclass.
  r, out = _run("demo.inherit")
  assert r.returncode == 0, out
  assert re.search(r"issubclass/Sequence,Container .*\b1\b", out), out
  assert re.search(r"issubclass/Container,Sequence .*not-a-subclass = \[\]", out), out


def test_ambients_registry_seed_macros():
  # hermetic (plain make, no hosted/interpret): the core registry-family macros on
  # __ambients__ -- `.has` tests NAME membership, `__ambients__.declare` appends the bare
  # `NAME` (names-only; config lives on the instance), `.require` is has-guarded (idempotent).
  probe = REPO / ".tmp.ambients.probe.mk"
  probe.write_text(
    "before := $(call __ambients__.has,zeta)\n"
    "$(eval $(call __ambients__.require,zeta))\n"
    "after := $(call __ambients__.has,zeta)\n"
    "$(eval $(call __ambients__.require,zeta))\n"  # second require: no duplicate
    "list := $(__ambients__)\n"
    "probe:;@printf 'before=[%s] after=[%s] list=[%s]\\n' '$(before)' '$(after)' '$(list)'\n"
  )
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=60,
    )
    out = _ANSI.sub("", r.stdout + r.stderr)
    assert "before=[]" in out, out
    assert "after=[zeta]" in out, out
    # idempotent: two `.require` calls -> zeta appears exactly once in the registry
    # (which is pre-seeded with the host machines host.native.sh/bash/python + out).
    list_val = re.search(r"list=\[([^\]]*)\]", out)
    assert list_val and list_val.group(1).split().count("zeta") == 1, out
  finally:
    probe.unlink(missing_ok=True)


def test_data_model_includes_derived_protocols():
  # the derived protocols self-register too; `lang.proto.registry` accumulates them after
  # the built-ins and the user-declared `hashable`.
  r, out = _run("demo.model")
  assert r.returncode == 0, out
  assert "Documented Registry Named Loggable Directory Program Openable Callable Templatable Materializable Feedable Runnable Ambient Language Hashable Container Sequence" in out


def test_concretized_protocols_ship_a_default_impl():
  # the concretized family (Callable/Runnable/Templatable) ships a default impl, so it flags
  # `.__concretized__` and publishes a non-empty `.__mixins` (stamped onto conformers via `bases=`);
  # structural protocols (Registry/Named) have an empty body and neither.  Templatable/Callable draw their
  # default from the shared seed prelude, so `.__mixins` names that mixin body -- Templatable's is a working
  # default, Callable's a fault stub.
  r, out = _run("demo.concretized")
  assert r.returncode == 0, out
  assert re.search(r"Templatable concretized .*\b1\b.*abstract=__mod__.*mixins=lang\.proto\.tmpl\.templatable Templatable", out), out
  assert re.search(r"Callable concretized .*\b1\b", out), out
  assert "structural = []" in out, out


def test_concretized_default_faults_when_not_overridden(tmp_path):
  # a CONCRETIZED protocol ships a default IMPL; for Callable/Runnable it is a FAULT stub.  Mixing
  # `bases=Callable` WITHOUT overriding `.__call__` -> invoking faults with "not implemented".  Pins the
  # fault-floor mechanism (protocol `default=` -> `.__mixins` -> `m5.tmpl/seed` onto the conformer).
  f = tmp_path / "fault.cmk"
  f.write_text(
    "from cmk import class\n"
    "class widget(bases=Callable)[| ${self}.x := 1 |]\n"
    "cmk.widget(w)\n"
    "demo:; @printf '%s' '$(call w.__call__)'\n"
    "__main__: demo\n"
  )
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=120,
  )
  out = _ANSI.sub("", r.stdout + r.stderr)
  assert r.returncode != 0, out               # the $(error) fault aborts
  assert ".__call__ not implemented" in out, out
  assert "Callable" in out, out               # names the protocol whose default fired


def test_protocol_tooling_does_not_leak_onto_conformers():
  # the valuable-real-estate guarantee: a protocol's body is the MIXIN (stamped onto conformers via
  # `bases=`), but its query/reader tooling (`.get`) lives on the protocol OBJECT (subject passed as
  # an arg) and is NEVER stamped.  So a conformer inherits the body member but not the tooling -- the
  # `.get` name stays free.  Driven by the demo's Described protocol + gadget instance.
  r, out = _run("demo.surface")
  assert r.returncode == 0, out
  assert re.search(r"gadget\.describe .*inherited body = \[file\]", out), out   # body member inherited
  assert re.search(r"gadget\.get origin .*not-inherited = undefined", out), out # tooling did NOT leak
  assert "query still works = a described thing" in out, out                    # reader still answers


@pytest.mark.docstring
def test_structural_base_does_not_clobber_conformer_docstring(tmp_path):
  # a docstring-only (structural) protocol used as a base stamps nothing -- so it does not overwrite a
  # conformer's own `.__doc__`.  Pins the concretized gate: an empty/docstring-only body is not a mixin.
  f = tmp_path / "noclobber.cmk"
  f.write_text(
    "from cmk import protocol, class\n"
    "protocol Marker(dunder=__mark__)(|\n"
    "  '''the Marker protocol, docstring only'''\n"
    "|)\n"
    "class thing(bases=Marker)[| ${self}.__doc__ := my own doc |]\n"
    "cmk.thing(t)\n"
    "demo:; @printf 'conc=[%s] doc=[%s]' "
    "'$(Marker.__concretized__)' '$(t.__doc__)'\n"
    "__main__: demo\n"
  )
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=120,
  )
  out = _ANSI.sub("", r.stdout + r.stderr)
  assert r.returncode == 0, out
  assert "conc=[]" in out, out                 # docstring-only body -> structural, not a mixin
  assert "doc=[my own doc]" in out, out         # conformer's own __doc__ survives (no clobber)


def test_no_protocol_name_is_shadowed():
  # regression for the `docstring`(protocol) vs `docstring`(awk-block) make-var COLLISION: every
  # registered protocol must still read its OWN contract -- i.e. a non-empty `.abstract`.  A shadowed
  # name (its `$(value)` overwritten by an unrelated define) yields an empty abstract; this catches that
  # whole class of bug (it was found only incidentally, by a declaration reorder).
  probe = REPO / ".tmp.protoshadow.mk"
  probe.write_text(
    "probe:\n\t@$(foreach _p,$(lang.proto.registry),printf '%s=[%s]\\n' '$(_p)' '$(strip $($(_p).abstract))';)\n"
  )
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=90,
    )
    out = _ANSI.sub("", r.stdout + r.stderr)
    rows = dict(re.findall(r"(\S+)=\[([^\]]*)\]", out))
    assert rows, out
    assert "Callable" in rows and "Documented" in rows, out   # hosted protocols actually loaded
    empty = sorted(p for p, a in rows.items() if not a.strip())
    assert not empty, f"protocols with empty .abstract (shadowed?): {empty}\n{out}"
  finally:
    probe.unlink(missing_ok=True)


def test_openable_reflects_the_open_seam():
  # `protocol Openable` (the mobility `open` capability -- ambient-protocol P1) abstracts the
  # per-kind `.__open__` method: `module`/`path` (which implement `.__open__`) conform; a kind
  # without a `.__open__` does not.  `Openable.provided_by/<k>` mirrors the `ambient.dissolve`
  # router's own `origin(<k>.__open__)` check -- so the seam is a first-class, reflectable interface.
  probe = REPO / ".tmp.openable.mk"
  probe.write_text(
    "probe:\n\t@printf 'abstract=[%s] module=[%s] path=[%s] registry=[%s]\\n' "
    "'$(Openable.abstract)' '$(call Openable.provided_by,module)' "
    "'$(call Openable.provided_by,path)' '$(call Openable.provided_by,registry)'\n"
  )
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=90,
    )
    out = _ANSI.sub("", r.stdout + r.stderr)
    assert "abstract=[__open__]" in out, out
    assert "module=[1]" in out and "path=[1]" in out, out   # both load-kinds conform
    assert "registry=[]" in out, out                        # no .__open__ -> not Openable
  finally:
    probe.unlink(missing_ok=True)


def test_directory_reflects_the_reflection_pair():
  # `protocol Directory` abstracts python's introspection PAIR -- `__all__` (INTENT, the `import *`
  # manifest) + `__dir__` (computed CONTENTS, the `dir()` member listing).  Structural + multi-member:
  # a carrier needs BOTH to conform (single-member carriers do not).  Note today the two providers live
  # APART -- `__all__` on core modules (cmk/dsl), `__dir__` on every class instance -- so neither alone
  # conforms; the contract names the unified interface a fully-reflective object (a module) will carry.
  probe = REPO / ".tmp.directory.mk"
  probe.write_text(
    "$(eval both.__all__ := a b)\n"
    "$(eval both.__dir__ := a b c)\n"
    "$(eval onlyall.__all__ := a b)\n"      # __all__ without __dir__
    "$(eval onlydir.__dir__ := a b c)\n"    # __dir__ without __all__
    "probe:\n\t@printf 'abstract=[%s] both=[%s] onlyall=[%s] onlydir=[%s]\\n' "
    "'$(Directory.abstract)' '$(call Directory.provided_by,both)' "
    "'$(call Directory.provided_by,onlyall)' '$(call Directory.provided_by,onlydir)'\n"
  )
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=90,
    )
    out = _ANSI.sub("", r.stdout + r.stderr)
    assert "abstract=[__all__ __dir__]" in out, out         # the reflection pair
    assert "both=[1]" in out, out                           # both members -> conforms
    assert "onlyall=[]" in out and "onlydir=[]" in out, out  # either alone -> not a Directory
  finally:
    probe.unlink(missing_ok=True)


def test_ctor_protocol_split_boundary():
  # The `cmk.protocol` ctor is split into `lang.proto.__new__` (IDENTITY: `.__isprotocol__`,
  # `.dunder`) and `lang.proto.__init__` (STRUCTURE: `.__bases__`/`.__mro__`/`.abstract`/
  # `.__mixins`), mirroring `lang.class.__new__`/`__init__`.  This pins the SEAM the split created:
  # __new__ stamps identity but NO structure; __init__ then builds structure and reads the dunder
  # __new__ set (proving the ordering).  Called directly, hermetically -- no protocol declaration.
  probe = REPO / ".tmp.protosplit.mk"
  probe.write_text(
    "$(eval $(call lang.proto.__new__, MyP, dunder=__foo__))\n"
    "n_isproto := $(MyP.__isprotocol__)\n"
    "n_dunder  := $(MyP.dunder)\n"
    "n_hasmro  := $(if $(filter-out undefined,$(origin MyP.__mro__)),yes,no)\n"
    "n_hasmix  := $(if $(filter-out undefined,$(origin MyP.__mixins)),yes,no)\n"
    "$(eval $(call lang.proto.__init__, MyP, dunder=__foo__))\n"
    "i_mro     := $(MyP.__mro__)\n"
    "i_abstract:= $(MyP.abstract)\n"
    "i_hasmix  := $(if $(filter-out undefined,$(origin MyP.__mixins)),yes,no)\n"
    "probe:\n\t@printf 'isproto=[%s] dunder=[%s] n_hasmro=[%s] n_hasmix=[%s] "
    "i_mro=[%s] abstract=[%s] i_hasmix=[%s]\\n' '$(n_isproto)' '$(n_dunder)' "
    "'$(n_hasmro)' '$(n_hasmix)' '$(i_mro)' '$(i_abstract)' '$(i_hasmix)'\n"
  )
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=90,
    )
    out = _ANSI.sub("", r.stdout + r.stderr)
    assert "isproto=[1]" in out, out            # __new__: type identity
    assert "dunder=[__foo__]" in out, out        # __new__: defining dunder
    assert "n_hasmro=[no]" in out, out           # SEAM: __new__ sets NO structure
    assert "n_hasmix=[no]" in out, out
    assert "i_mro=[MyP]" in out, out             # __init__: structure assembled
    assert "abstract=[__foo__]" in out, out       # __init__ reads the dunder __new__ set (ordering)
    assert "i_hasmix=[yes]" in out, out          # __init__ DEFINES .__mixins (empty ok)
  finally:
    probe.unlink(missing_ok=True)
