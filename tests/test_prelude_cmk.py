"""Opt-in `cmk` prelude.

The declaration keywords (class/constructor/container/machine/dsl) live
qualified as `cmk.*` and are always available; they are bound bare ONLY via
`from cmk import *` / `from cmk import ..` (or the older `open cmk` aliases).  Reaching a bare keyword
without pulling it in is an error -- that is the opt-in that frees the bare word
for a DSL author.  See docs/compiler (the prelude section) + TODO-prelude-scope.md.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler

REPO = Path(__file__).resolve().parent.parent


def _origins(cmk, head, names=("class", "container")):
  # run a tiny cmk file whose `probe` target prints `$(origin NAME)` per name;
  # `open`/`from` directives in `head` decide which are bound bare.  Mirrors the
  # supervisor-on run pattern (CMK_SUPERVISOR=1) so a passed goal + piped stdin
  # dispatch cleanly.  File lands in REPO (relative arg) and is cleaned up.
  echo = " ".join("%s=[$(origin %s)]" % (n, n) for n in names)
  src = "%s\nprobe:\n\t@printf '%s\\n'\n" % (head, echo)
  name = ".tmp.prelude_probe.%d.cmk" % (abs(hash(head)) % 100000)
  p = REPO / name
  p.write_text(src)
  try:
    r = cmk("cmk", "run", name, "probe", cwd=REPO, timeout=90,
            env={"CMK_SUPERVISOR": "1"})
    return r.stdout + r.stderr
  finally:
    p.unlink(missing_ok=True)


def test_bare_keyword_undefined_without_open(cmk):
  # no directive: bare keywords are NOT defined -- the whole point of opt-in.
  out = _origins(cmk, "# nothing pulled in")
  assert "class=[undefined]" in out, out[-800:]
  assert "container=[undefined]" in out, out[-800:]


def test_open_binds_all_bare(cmk):
  # `open cmk` binds every prelude keyword bare.
  out = _origins(cmk, "open cmk")
  assert "class=[undefined]" not in out, out[-800:]
  assert "container=[undefined]" not in out, out[-800:]


def test_from_import_binds_only_listed(cmk):
  # `from cmk import class` binds ONLY `class`; `container` stays free.
  out = _origins(cmk, "from cmk import class")
  assert "class=[undefined]" not in out, out[-800:]
  assert "container=[undefined]" in out, out[-800:]


def test_from_import_star_binds_all(cmk):
  # `from cmk import *` is the preferred spelling for binding every prelude keyword
  # bare -- same lowering as `open cmk`.
  out = _origins(cmk, "from cmk import *")
  assert "class=[undefined]" not in out, out[-800:]
  assert "container=[undefined]" not in out, out[-800:]


def test_from_import_star_except_frees_listed(cmk):
  # `from cmk import * except container` binds all bare EXCEPT the listed name --
  # parity with `open cmk except container`.
  out = _origins(cmk, "from cmk import * except container")
  assert "class=[undefined]" not in out, out[-800:]
  assert "container=[undefined]" in out, out[-800:]


def test_dsl_reached_via_cmk_prelude(cmk):
  # `dsl` is a member of the `cmk` prelude, NOT its own star-importable module: `from cmk import dsl`
  # binds `dsl` bare (the metaclass), and the built-in kinds are used qualified (`dsl.jqlang` /
  # `dsl.awklang`).  There is no `from dsl import *` (dsl carries no manifest).
  out = _origins(cmk, "from cmk import dsl", names=("dsl",))
  assert "dsl=[undefined]" not in out, out[-800:]


def test_open_except_frees_listed(cmk):
  # `open cmk except container` binds all bare EXCEPT the listed name.
  out = _origins(cmk, "open cmk except container")
  assert "class=[undefined]" not in out, out[-800:]
  assert "container=[undefined]" in out, out[-800:]


def test_import_cmk_is_noop(cmk):
  # `import cmk` is declarative only (the `cmk.*` forms always exist); it does not
  # bind bare names.
  out = _origins(cmk, "import cmk")
  assert "class=[undefined]" in out, out[-800:]


def test_namespace_is_prelude_keyword(cmk):
  # `namespace` joins the prelude: undefined bare until `open cmk`, then bound.
  assert "namespace=[undefined]" in _origins(cmk, "# nothing", names=("namespace",))
  assert "namespace=[undefined]" not in _origins(cmk, "open cmk", names=("namespace",))


def test_namespace_nested_qualifies(cmk):
  # the `namespace` kind: nested blocks thread `${__name__}`, so a bare head under
  # `namespace a[| namespace b[| foo: |] |]` lands as the target `a.b.foo` (which
  # runs) and the instance records `${a.b.__name__} == a.b`.
  src = (
    "open cmk\n"
    "namespace a[|\n  namespace b[|\n    foo:; @echo NS_HI\n  |]\n|]\n"
    "probe: a.b.foo\n\t@printf 'name=[${a.b.__name__}]\\n'\n"
  )
  name = ".tmp.ns_nested_probe.cmk"
  p = REPO / name
  p.write_text(src)
  try:
    r = cmk("cmk", "run", name, "probe", cwd=REPO, timeout=90,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "NS_HI" in out, out[-800:]
    assert "name=[a.b]" in out, out[-800:]
  finally:
    p.unlink(missing_ok=True)
    for leftover in REPO.glob(".tmp.ns.*"):
      leftover.unlink(missing_ok=True)


def test_qualified_banana_lowers(ir):
  # the always-on qualified escape: `cmk.class Foo[| .. |]` survives the structural
  # banana-aware anchor and lowers to a literal `$(call cmk.class, def=Foo)`.
  r = ir("cmk.class Foo[|\n  ${self}.x = 1\n|]\n")
  assert "$(call cmk.class, def=Foo)" in r.stdout, r.stdout[-800:]


def test_qualified_callform_still_anchors(ir):
  # regression: a `cmk.NAME(..)` callform (NOT a banana head) still anchors and
  # lowers to `$(call NAME, ..)` -- the anchor move did not break ordinary callforms.
  r = ir("foo:\n\tcmk.log(hi)\n")
  assert "$(call log,hi)" in r.stdout, r.stdout[-800:]


# ---------------------------------------------------------------------------
# host.native as an importable module.
#
# `host.native.bash` is an in-memory namespace (a cmk.host instance), NOT a disk
# plugin.  `from host.native import bash` binds the short handle `bash` to that
# namespace so `bash.polyglot NAME(| .. |)` dispatches to the real host runner --
# exactly the canonical `host.native.bash.polyglot NAME(| .. |)` (see
# demos/cmk/host-native-bash.cmk).  host.native is a first-class module JUST
# LIKE `cmk` above: it declares `host.native.__all__` (bash sh python), and the
# core-module set is derived from `%.__all__`.  Its members are namespace-only (a
# `host.native.<x>` has sub-attrs but no leaf value), which lang.module.bind binds.
#
# The `import host.native.bash as bash` RENAME form is still unsupported (xfail):
# the `import .. as` acquire arm routes to the disk-plugin loader (kind=path), not
# an in-memory-prefix alias.
# ---------------------------------------------------------------------------


def _run_head(cmk, head, token="HN_BASH_RAN"):
  # run a cmk file whose `script.sh` is a host-bash polyglot printing `token`, gated
  # behind the `head` import directive that should bind the bare `bash` handle.
  # `probe` depends on script.sh so the goal drives it.  POSITIVE assertion target
  # (the token proves the import bound `bash` AND dispatched to the host runner).
  src = (
    "%s\n"
    "bash.polyglot script.sh(|\n"
    "  printf '%s\\n'\n"
    "|)\n"
    "probe: script.sh\n"
    "\t@printf 'PROBE_DONE\\n'\n"
  ) % (head, token)
  name = ".tmp.hn_module.%d.cmk" % (abs(hash(head)) % 100000)
  p = REPO / name
  p.write_text(src)
  try:
    r = cmk("cmk", "run", name, "probe", cwd=REPO, timeout=90,
            env={"CMK_SUPERVISOR": "1"})
    return r.stdout + r.stderr
  finally:
    p.unlink(missing_ok=True)


def test_from_host_native_import_bash_runs(cmk):
  # `from host.native import bash` binds `bash` -> `bash.polyglot` dispatches to the
  # real host bash runner; the script runs on the host.
  out = _run_head(cmk, "from host.native import bash")
  assert "HN_BASH_RAN" in out, out[-800:]


def test_from_host_native_import_star_runs(cmk):
  # `from host.native import *` binds every host.native.__all__ member bare
  # (bash/sh/python); `bash.polyglot` then runs.
  out = _run_head(cmk, "from host.native import *")
  assert "HN_BASH_RAN" in out, out[-800:]


def test_from_host_native_import_bash_binds_member(cmk):
  # parity with the `from cmk import ..` origin probes: `bash.polyglot` becomes a
  # defined (bound-bare) member after the import (namespace-only member, no leaf).
  src = ("from host.native import bash\n"
         "probe:\n\t@printf 'bash.polyglot=[$(origin bash.polyglot)]\\n'\n")
  name = ".tmp.hn_origin.cmk"
  p = REPO / name
  p.write_text(src)
  try:
    r = cmk("cmk", "run", name, "probe", cwd=REPO, timeout=90,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
  finally:
    p.unlink(missing_ok=True)
  assert "bash.polyglot=[file]" in out, out[-800:]


@pytest.mark.xfail(
  reason="the `import .. as` rename form still routes an in-memory namespace prefix "
  "to the disk-plugin loader (emit_pathdis -> ambient.dissolve kind=path) instead of "
  "lang.module.bind, so `import host.native.bash as bash` errors on a missing plugin. "
  "Fix needs the import-as acquire arm to detect an existing make-var prefix and route "
  "to lang.module.bind (with the alias as the rename target).",
  strict=True,
)
def test_import_host_native_bash_as_alias_runs(cmk):
  # `import host.native.bash as bash` should alias the in-memory namespace under
  # `bash` (rename-on-import), NOT a disk-plugin load; `bash.polyglot` runs.
  out = _run_head(cmk, "import host.native.bash as bash")
  assert "HN_BASH_RAN" in out, out[-800:]


# ---------------------------------------------------------------------------
# import trailer syntax: a kw=v trailer is comma-delimited (`as <ns>, flat=1`).
# The bare space form reads like a typo and is a parse fault; a trailing comma
# continues onto the next (optionally indented) line; directives may be indented.
# ---------------------------------------------------------------------------


def _transpile(cmk, head):
  # lower a directive to its Makefile fragment (no eval) via `lang.transpile` on
  # stdin -- no temp file, no run.  A parse fault emits its `$(error ..)` as
  # literal fragment text, so both the lowering and the fault are assertable.
  src = "%s\nprobe:;@true\n" % head
  r = cmk("lang.transpile", stdin=src, cwd=REPO, timeout=90)
  return r.stdout + r.stderr


def test_import_trailer_comma_form_lowers(cmk):
  # `import <src> as <ns>, flat=1` -- the canonical comma trailer lowers cleanly
  # to a path dissolve.  `def=__opena` is unique to lowered import output (the
  # compiler source only ever emits the disjoint `def=" d "`), so it is a clean
  # positive signal even when a noisy error path echoes the source back.
  out = _transpile(cmk, "import virtual-machine.cmk as vm, flat=1")
  assert "def=__opena" in out, out[-800:]


def test_import_trailer_space_form_faults(cmk):
  # bare `import <src> as <ns> flat=1` (no comma) reads like a typo -> parse fault.
  out = _transpile(cmk, "import virtual-machine.cmk as vm flat=1")
  assert "import trailer needs a comma" in out, out[-800:]


def test_import_trailer_noas_space_form_faults(cmk):
  # the same rule holds without `as`: `import mymod targets=..` must be comma-led.
  out = _transpile(cmk, "import mymod targets='build.*'")
  assert "import trailer needs a comma" in out, out[-800:]


def test_import_trailer_newline_continuation(cmk):
  # a trailing comma continues onto the next (indented) line: the trailer wraps.
  out = _transpile(cmk, "import virtual-machine.cmk as vm,\n  flat=1")
  assert "def=__opena" in out, out[-800:]


def test_import_directive_indent_tolerated(cmk):
  # a leading-indented `import .. as .., kw=v` is recognized (indent-normalized).
  out = _transpile(cmk, "  import virtual-machine.cmk as vm, flat=1")
  assert "def=__opena" in out, out[-800:]


# ---------------------------------------------------------------------------
# `<module>.import(..)` -- instance-method form of import.module (implemented).
# The cmk.module class defines `.import` as a partial over the static import.module,
# binding `def=<self>` (its own name).  A `module NAME[| .. |]` instance thus carries
# `NAME.import(namespace=..)` == `import.module(def=NAME namespace=..)` -- the instance
# analog of the demo's static `cmk.import.module(def=MyModule namespace=Aliased)`.
# ---------------------------------------------------------------------------


def test_module_has_import_instance_method(cmk):
  # a `module NAME[| .. |]` (a cmk.module instance) carries `.import`; calling it mounts
  # the module under `Aliased.*`, so `Aliased.greet` is a runnable target (GREET_RAN).
  # `MyModule.import(namespace=Aliased)` lowers to `$(call import.module, def=MyModule ..)`.
  src = (
    "from cmk import module\n"
    "module MyModule[|\n"
    "  greet:; cmk.log(GREET_RAN)\n"
    "|]\n"
    "MyModule.import(namespace=Aliased)\n"
    "probe: Aliased.greet\n"
    "\t@printf 'PROBE_DONE\\n'\n"
  )
  name = ".tmp.mod_import_method.cmk"
  p = REPO / name
  p.write_text(src)
  try:
    r = cmk("cmk", "run", name, "probe", cwd=REPO, timeout=90,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
  finally:
    p.unlink(missing_ok=True)
  assert "GREET_RAN" in out, out[-800:]
