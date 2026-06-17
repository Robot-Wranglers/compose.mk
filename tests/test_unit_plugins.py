"""Unit tests for compose.mk's PLUGIN/import system (no docker).

The plugin family resolves a makefile under ${CMK_PLUGINS_DIR} (default `.cmk`)
and `include`s it, logging the import and -- for the strict variant -- erroring
cleanly when it is absent:

  - mk.include.plugin        -- strict (default): $(error CMK_INCLUDE_MISSING) if
                                absent; pass strict=0 for lenient (log + continue)
  - mk.include.plugins       -- many at once
  - mk.include.files         -- many, but cwd-relative (prefix=.) not plugins-dir
  - mk.include.file          -- one explicit path (tested in test_unit_macros.py)
  - mk.import.module         -- stage a def= OR file= into CMK_MODULES_DIR, import

Each test builds a tiny wrapper Makefile that `include`s compose.mk, drops the
plugin file(s) under a temp plugins-dir, and asserts the import's effect. The
cmk fixture runs from a tmp cwd, so a relative `.cmk` lands there (never the
repo's real `.cmk`).
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrapper(tmp_path, body: str) -> Path:
  mk = tmp_path / "wrap.mk"
  mk.write_text(f"include {COMPOSE_MK}\n{body}\n")
  return mk


def _plugin(dir_: Path, name: str, body: str) -> None:
  dir_.mkdir(parents=True, exist_ok=True)
  (dir_ / name).write_text(body)


# --- mk.include.plugin (strict) -----------------------------------------------


def test_import_plugin_present(cmk, tmp_path):
  # A present plugin under the default plugins-dir (.cmk) is included, so its
  # definitions become available to the importer.
  _plugin(tmp_path / ".cmk", "greeting.mk", "GREETING := hello-from-plugin\n")
  body = (
    "$(call mk.include.plugin, greeting.mk)\n"
    "probe:; @printf 'G=[%s]\\n' '$(GREETING)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "G=[hello-from-plugin]" in r.stdout


def test_import_plugin_strict_missing_errors(cmk, tmp_path):
  # A missing plugin under the strict variant fails the build (CMK_INCLUDE_MISSING).
  body = "$(call mk.include.plugin, nope.mk)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_INCLUDE_MISSING" in r.stderr


# --- mk.include.plugin strict=0 (lenient) ------------------------------------


def test_import_plugin_lenient_missing_tolerated(cmk, tmp_path):
  # strict=0 does NOT error when the plugin is absent -- the build continues and
  # the target still runs.
  body = "$(call mk.include.plugin, file=nope.mk strict=0)\nprobe:; @echo CONTINUED\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "CONTINUED" in r.stdout


def test_import_plugin_lenient_present_still_includes(cmk, tmp_path):
  # When the plugin IS present, strict=0 includes it like the strict default.
  _plugin(tmp_path / ".cmk", "opt.mk", "OPT := on\n")
  body = (
    "$(call mk.include.plugin, file=opt.mk strict=0)\n"
    "probe:; @printf 'OPT=[%s]\\n' '$(OPT)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "OPT=[on]" in r.stdout


# --- mk.include.plugins (many) ------------------------------------------------


def test_import_plugins_multiple(cmk, tmp_path):
  # Several plugins imported in one call; all of their defs become available.
  _plugin(tmp_path / ".cmk", "a.mk", "A := 1\n")
  _plugin(tmp_path / ".cmk", "b.mk", "B := 2\n")
  body = (
    "$(call mk.include.plugins, a.mk b.mk)\n"
    "probe:; @printf 'A=[%s] B=[%s]\\n' '$(A)' '$(B)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "A=[1] B=[2]" in r.stdout


# --- cmk-lang plugins (.cmk -> JIT-compile then include) ----------------------
# A plugin whose name ends in `.cmk` is LOWERED (mk.compile) at include time and
# the staged result is included at root; a plain `.mk` plugin keeps the fast,
# copy-free `include` (no staging). See _mk.include.plugins in compose.mk.

# cmk-lang body using the `this.` dialect (this.X -> ${make} X): only valid AFTER
# lowering, so a successful run proves the plugin was compiled, not copied.
_CMK_PLUGIN = "plug.inner:; @echo LOWERED_OK\nplug.hello:\n\tthis.plug.inner\n"


def test_include_plugin_cmk_is_lowered_and_staged(cmk, tmp_path):
  _plugin(tmp_path / ".cmk", "greeter.cmk", _CMK_PLUGIN)
  body = "$(call mk.include.plugin, greeter.cmk)\nprobe: plug.hello\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "LOWERED_OK" in r.stdout
  # the compile path stages a materialized module under CMK_MODULES_DIR (.cmk);
  # a file-import's staged key carries a content digest -> `.tmp.module.greeter-<hash>.mk`
  assert list((tmp_path / ".cmk").glob(".tmp.module.greeter-*.mk"))


def test_include_plugin_mk_stays_fast_no_staging(cmk, tmp_path):
  # A plain `.mk` plugin must NOT go through staging -- it keeps the verbatim
  # `include` fast path, so no `.tmp.module.*` is materialized for it.
  _plugin(tmp_path / ".cmk", "plain.mk", "PLAIN := yes\n")
  body = (
    "$(call mk.include.plugin, plain.mk)\n"
    "probe:; @printf 'P=[%s]\\n' '$(PLAIN)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "P=[yes]" in r.stdout
  assert not list((tmp_path / ".cmk").glob(".tmp.module.*"))


def test_include_plugins_mixed_mk_and_cmk(cmk, tmp_path):
  # One call with both extensions: each binds via its own path.
  _plugin(tmp_path / ".cmk", "plain.mk", "PLAIN := yes\n")
  _plugin(tmp_path / ".cmk", "greeter.cmk", _CMK_PLUGIN)
  body = (
    "$(call mk.include.plugins, plain.mk greeter.cmk)\n"
    "probe: plug.hello\n\t@printf 'P=[%s]\\n' '$(PLAIN)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "LOWERED_OK" in r.stdout
  assert "P=[yes]" in r.stdout


def test_include_plugin_cmk_extension_variants(cmk, tmp_path):
  # The cmk-lang (compile) path is taken for `.CMK` and the `.cmk.mk`
  # double-extension too, not just lowercase `.cmk`. A plugin with cmk sugar
  # under either spelling must lower and run.
  _plugin(tmp_path / ".cmk", "up.CMK", _CMK_PLUGIN.replace("plug.", "up."))
  _plugin(
    tmp_path / ".cmk", "dbl.cmk.mk", _CMK_PLUGIN.replace("plug.", "dbl.")
  )
  body = (
    "$(call mk.include.plugins, up.CMK dbl.cmk.mk)\n"
    "probe: up.hello dbl.hello\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  # _CMK_PLUGIN's `this.` target echoes LOWERED_OK from each lowered plugin
  assert r.stdout.count("LOWERED_OK") == 2


def test_include_plugin_cmk_strict_missing_errors(cmk, tmp_path):
  # Missing `.cmk` under the strict default fails like a missing `.mk` plugin.
  body = "$(call mk.include.plugin, nope.cmk)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_INCLUDE_MISSING" in r.stderr


def test_include_plugin_cmk_lenient_missing_tolerated(cmk, tmp_path):
  # strict=0 makes an absent `.cmk` plugin a no-op (parity with `.mk`).
  body = "$(call mk.include.plugin, file=nope.cmk strict=0)\nprobe:; @echo CONTINUED\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "CONTINUED" in r.stdout


# --- CMK_PLUGINS_DIR is configurable -----------------------------------------


def test_import_plugin_custom_plugins_dir(cmk, tmp_path):
  # CMK_PLUGINS_DIR redirects where plugins are resolved from.
  plugdir = tmp_path / "vendor"
  _plugin(plugdir, "vend.mk", "VEND := yep\n")
  body = (
    "$(call mk.include.plugin, vend.mk)\n"
    "probe:; @printf 'VEND=[%s]\\n' '$(VEND)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_PLUGINS_DIR": str(plugdir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "VEND=[yep]" in r.stdout


# --- mk.include.files (cwd-relative, not plugins-dir) -------------------------


def test_import_files_relative(cmk, tmp_path):
  # mk.include.files includes by cwd-relative path (prefix=.), independent of
  # CMK_PLUGINS_DIR.
  (tmp_path / "local.mk").write_text("LOCAL := here\n")
  body = (
    "$(call mk.include.files, local.mk)\n"
    "probe:; @printf 'LOCAL=[%s]\\n' '$(LOCAL)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "LOCAL=[here]" in r.stdout


# --- mk.import.module: stage a def OR file into CMK_MODULES_DIR, then import --
# Modules are NAMESPACED: every module-level assignment LHS / target-name is
# prefixed with $(CMK_MODULE) (= the module name), so a module `m` defining
# `var`/`tgt` is referenced as `m.var` / `m.tgt` (the bare names aren't defined).


def test_import_module_from_def_vars(cmk, tmp_path):
  # An in-scope `define` is staged + imported; its vars are available under the
  # module namespace (my_plugin.FROM_DEF).
  body = (
    "define my_plugin\n"
    "FROM_DEF := def-plugin-loaded\n"
    "endef\n"
    "$(call mk.import.module, def=my_plugin)\n"
    "probe:; @printf 'FROM_DEF=[%s]\\n' '$(my_plugin.FROM_DEF)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "FROM_DEF=[def-plugin-loaded]" in r.stdout


def test_import_module_from_def_target(cmk, tmp_path):
  # A TARGET in the module is runnable under the namespace (tgt_plugin.hello).
  body = (
    "define tgt_plugin\n"
    "hello:; @echo hello-from-def-plugin\n"
    "endef\n"
    "$(call mk.import.module, def=tgt_plugin)\n"
  )
  r = cmk("tgt_plugin.hello", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "hello-from-def-plugin" in r.stdout


def test_import_module_namespaces_and_hides_bare_names(cmk, tmp_path):
  # The namespacing is real: `var1` is reachable as `mod.var1`, and the BARE
  # `var1` is NOT defined.
  body = (
    "define mod\n"
    "var1:=val1\n"
    "endef\n"
    "$(call mk.import.module, def=mod)\n"
    "probe:; @printf 'ns=[%s] bare=[%s]\\n' '$(mod.var1)' '$(var1)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "ns=[val1] bare=[]" in r.stdout


def test_import_module_from_def_missing_errors(cmk, tmp_path):
  # An undefined def name fails cleanly rather than silently importing nothing.
  body = "$(call mk.import.module, def=nope_block)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_MODULE_MISSING" in r.stderr


def test_import_module_from_file(cmk, tmp_path):
  # file=<path>: copied into CMK_MODULES_DIR and imported; namespace = the
  # basename sans extension (mod_src).
  (tmp_path / "mod_src.mk").write_text("FROM_FILE := file-module\n")
  body = (
    "$(call mk.import.module, file=mod_src.mk)\n"
    "probe:; @printf 'FROM_FILE=[%s]\\n' '$(mod_src.FROM_FILE)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "FROM_FILE=[file-module]" in r.stdout


def test_import_module_file_missing_errors(cmk, tmp_path):
  # file= pointing at a nonexistent path fails cleanly.
  body = "$(call mk.import.module, file=nope.mk)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_MODULE_MISSING" in r.stderr


def test_import_module_def_and_file_mutually_exclusive(cmk, tmp_path):
  # Passing BOTH def= and file= is an error.
  (tmp_path / "m.mk").write_text("X := 1\n")
  body = (
    "define d\nY := 2\nendef\n"
    "$(call mk.import.module, def=d file=m.mk)\n"
    "probe:; @true\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_MODULE_ARGS" in r.stderr


def test_import_module_requires_def_or_file(cmk, tmp_path):
  # Passing NEITHER def= nor file= is an error.
  body = "$(call mk.import.module, color=red)\nprobe:; @true\n"
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_MODULE_ARGS" in r.stderr


def test_import_module_custom_modules_dir(cmk, tmp_path):
  # CMK_MODULES_DIR controls where modules are STAGED (and imported from),
  # independent of CMK_PLUGINS_DIR.
  moddir = tmp_path / "modules"
  body = (
    "define m\nMOD := from-custom-dir\nendef\n"
    "$(call mk.import.module, def=m)\n"
    "probe:; @printf 'MOD=[%s]\\n' '$(m.MOD)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "MOD=[from-custom-dir]" in r.stdout
  assert (moddir / ".tmp.module.m.mk").exists()  # staged under CMK_MODULES_DIR


def test_import_module_injects_cmk_module_for_def(cmk, tmp_path):
  # mk.import.module injects `export CMK_MODULE := <name>` at the top of the
  # staged module, so its recipes can read their own identity via $CMK_MODULE.
  body = (
    "define mymod\n"
    "show:; @printf 'CMK_MODULE=[%s]\\n' \"$$CMK_MODULE\"\n"
    "endef\n"
    "$(call mk.import.module, def=mymod)\n"
  )
  r = cmk("mymod.show", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "CMK_MODULE=[mymod]" in r.stdout  # = the def name


def test_import_module_injects_cmk_module_for_file(cmk, tmp_path):
  # For file=, the injected CMK_MODULE is the basename (sans extension).
  (tmp_path / "foo.mk").write_text(
    "show:; @printf 'CMK_MODULE=[%s]\\n' \"$$CMK_MODULE\"\n"
  )
  body = "$(call mk.import.module, file=foo.mk)\n"
  r = cmk("foo.show", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "CMK_MODULE=[foo]" in r.stdout  # = the file basename


def test_import_module_namespace_override_def(cmk, tmp_path):
  # namespace= overrides the destination PREFIX (vars land under `alias.`, not the
  # def name).  But CMK_MODULE is the module's own SOURCE identity (the def name),
  # NOT the destination alias -- a module reads the same identity however it's
  # imported.
  body = (
    "define modyool\n"
    "var1:=val1\n"
    "endef\n"
    "$(call mk.import.module, def=modyool namespace=alias)\n"
    "probe:; @printf 'alias=[%s] def=[%s] mod=[%s]\\n' "
    "'$(alias.var1)' '$(modyool.var1)' '$(CMK_MODULE)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "alias=[val1] def=[] mod=[modyool]" in r.stdout


def test_import_module_namespace_override_file(cmk, tmp_path):
  # namespace= overrides the destination prefix for file= too; CMK_MODULE is the
  # SOURCE identity (the basename `src`), not the destination alias.
  (tmp_path / "src.mk").write_text("var1:=v\n")
  body = (
    "$(call mk.import.module, file=src.mk namespace=alias)\n"
    "probe:; @printf 'alias=[%s] base=[%s] mod=[%s]\\n' "
    "'$(alias.var1)' '$(src.var1)' '$(CMK_MODULE)'\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "alias=[v] base=[] mod=[src]" in r.stdout


def test_import_module_nested_define_body_is_verbatim(cmk, tmp_path):
  # A module may contain a NESTED `define ... endef`.  Its body is literal text,
  # so the namespace surgery must track define/endef depth and leave every line
  # inside verbatim -- even assignment-shaped ones.  Otherwise `INNER := survived`
  # would be rewritten to `$(CMK_MODULE).INNER := ...`, corrupting the snippet.
  # Here the nested snippet is eval'd at import: the bare `INNER` must resolve,
  # and the namespaced `mod.INNER` must stay UNdefined (the line was not mangled).
  body = (
    "define mod\n"
    "define snippet\n"
    "INNER := survived\n"
    "endef\n"
    "$(eval $(snippet))\n"
    "probe:; @printf 'INNER=[%s] nsd=[%s]\\n' '$(INNER)' '$(mod.INNER)'\n"
    "endef\n"
    "$(call mk.import.module, def=mod)\n"
  )
  r = cmk("mod.probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "INNER=[survived]" in r.stdout  # nested body preserved verbatim
  assert "nsd=[]" in r.stdout  # NOT namespaced into mod.INNER


def test_import_module_nested_define_outer_targets_still_namespaced(
  cmk, tmp_path
):
  # Depth tracking must not over-reach: a module-level target declared AFTER a
  # nested define closes is still namespaced (the `endef` popped depth back to 0).
  body = (
    "define mod2\n"
    "define _tmpl\n"
    "ignored:=x\n"
    "endef\n"
    "after:; @echo after-target-ran\n"
    "endef\n"
    "$(call mk.import.module, def=mod2)\n"
  )
  r = cmk("mod2.after", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "after-target-ran" in r.stdout


def test_import_module_compiles_embedded_cmk_lang(cmk, tmp_path):
  # KEY PROPERTY: a module body may contain CMK-Lang -- the `"""..."""` heredoc and
  # the `this.` dialect -- even though the host Makefile is run by PLAIN `make -f`
  # (no cmk interpreter).  `preprocs` defaults to mk.compile, so the staged COPY is
  # lowered to vanilla make.  i.e. mk.import.module lets you EMBED cmk-lang in a
  # vanilla Makefile.
  body = (
    "define greetmod\n"
    'hello:; """hi from embedded cmk-lang""" | this.stream.preview\n'
    "endef\n"
    "$(call mk.import.module, def=greetmod)\n"
  )
  r = cmk("greetmod.hello", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  # the heredoc lowered to printf + this.stream.preview to a recursive make, and
  # the greeting actually ran (stream.preview echoes its stdin to stderr).
  assert "hi from embedded cmk-lang" in (r.stdout + r.stderr)


def test_import_module_does_not_mutate_source_define(cmk, tmp_path):
  # Importing compiles a COPY (the staged `.tmp.module.*.mk`); the source `define`
  # is never touched.  The define here holds CMK-Lang; after import, mk.def.read
  # still shows the original `"""..."""` verbatim (uncompiled) -- proving the
  # on-the-fly compilation pipeline does not mutate the source.
  body = (
    "define srcmod\n"
    'hello:; """untouched-source""" | this.stream.preview\n'
    "endef\n"
    "$(call mk.import.module, def=srcmod)\n"
  )
  r = cmk("mk.def.read/srcmod", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert '"""untouched-source"""' in (r.stdout + r.stderr)


def test_import_module_preprocs_is_a_swappable_pipeline(cmk, tmp_path):
  # `preprocs` is an arbitrary flux.pipeline run over the module body at stage time
  # (default mk.compile).  `preprocs=stream.echo` is a verbatim passthrough, so the
  # CMK-Lang is staged UN-lowered -- proving the pipeline is a real, swappable hook
  # (and, again, that the source is never mutated -- only the staged copy varies).
  moddir = tmp_path / "modules"
  body = (
    "define pmod\n"
    'hello:; """still-cmk-syntax""" | this.stream.preview\n'
    "endef\n"
    "$(call mk.import.module, def=pmod preprocs=stream.echo)\n"
    "probe:; @true\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  staged = (moddir / ".tmp.module.pmod.mk").read_text()
  assert (
    '"""still-cmk-syntax"""' in staged
  )  # stream.echo -> NOT lowered (verbatim)
  assert "printf '%s'" not in staged  # the heredoc was not compiled


def test_import_module_preprocs_pipeline_is_colon_delimited(cmk, tmp_path):
  # A MULTI-stage preprocs pipeline is COLON-delimited (`a:b`, routed through
  # flux.column) -- NOT comma, which make's `$(call)` would split before this
  # kwarg is ever read.  `stream.echo:mk.compile` stages the body verbatim, then
  # compiles it, so the heredoc IS lowered to a printf (proving both stages ran
  # and the colon delimiter chains them).
  moddir = tmp_path / "modules"
  body = (
    "define pmod\n"
    'hello:; """compile-me""" | this.stream.preview\n'
    "endef\n"
    "$(call mk.import.module, def=pmod preprocs=stream.echo:mk.compile)\n"
    "probe:; @true\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  staged = (moddir / ".tmp.module.pmod.mk").read_text()
  assert (
    '"""compile-me"""' not in staged
  )  # the colon-pipeline's mk.compile lowered it
  assert "printf '%s'" in staged  # heredoc compiled to a printf


def test_import_module_partial_by_targets(cmk, tmp_path):
  # A PARTIAL module import: `targets=` prepends a mk.select.targets stage so only
  # the matching target(s) are namespaced + imported; the rest are absent.
  moddir = tmp_path / "modules"
  body = (
    "define pm\n"
    "keep.first:\n"
    "\t@echo kept\n"
    "drop.second:\n"
    "\t@echo dropped\n"
    "endef\n"
    "$(call mk.import.module, def=pm targets='keep.*')\n"
    "probe:; @${make} pm.keep.first\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "kept" in r.stdout
  staged = (moddir / ".tmp.module.pm.mk").read_text()
  assert (
    "pm.keep.first" in staged
  )  # selected + namespaced (literal dest prefix)
  assert "drop.second" not in staged  # not selected


def test_import_module_partial_by_defs(cmk, tmp_path):
  # `defs=` selects define blocks by name/glob before namespacing.
  moddir = tmp_path / "modules"
  body = (
    "define pmd\n"
    "define salute\nhi\nendef\n"
    "define other\nno\nendef\n"
    "endef\n"
    "$(call mk.import.module, def=pmd defs='salute')\n"
    "probe:; @true\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  staged = (moddir / ".tmp.module.pmd.mk").read_text()
  assert "define salute" in staged  # selected
  assert "define other" not in staged  # not selected


def test_import_module_defs_and_targets_mutually_exclusive(cmk, tmp_path):
  # defs= and targets= cannot both be given.
  body = (
    "define pmx\n"
    "x:=1\n"
    "endef\n"
    "$(call mk.import.module, def=pmx defs='a' targets='b')\n"
    "probe:; @true\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert not r.ok
  assert "CMK_MODULE_ARGS" in r.stderr or "mutually exclusive" in r.stderr


def test_import_module_flat_compiled_def(cmk, tmp_path):
  # flat=1 omits the namespace + CMK_MODULE-header stages: the body lands in the
  # GLOBAL namespace (un-prefixed), still compiled.
  moddir = tmp_path / "modules"
  body = (
    "define flatmod\n"
    "FLATV := flat-ok\n"
    "endef\n"
    "$(call mk.import.module, def=flatmod flat=1)\n"
    "probe:; @printf 'bare=[%s] pref=[%s]\\n' '$(FLATV)' '$(flatmod.FLATV)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "bare=[flat-ok]" in r.stdout  # reachable un-namespaced (root)
  assert "pref=[]" in r.stdout  # NOT prefixed
  staged = (moddir / ".tmp.module.flatmod.mk").read_text()
  assert "CMK_MODULE" not in staged  # no identity header injected
  assert "$(CMK_MODULE)" not in staged  # no prefix applied


def test_import_module_flat_verbatim_file_is_fast_path(cmk, tmp_path):
  # flat + verbatim (stream.echo) + file = the fast-path: a direct, copy-free
  # include with NO staged copy written.
  moddir = tmp_path / "modules"
  inc = tmp_path / "plug.mk"
  inc.write_text("FROM_FLAT := yes\n")
  body = (
    f"$(call mk.import.module, file={inc} flat=1 preprocs=stream.echo)\n"
    "probe:; @printf 'FROM_FLAT=[%s]\\n' '$(FROM_FLAT)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "FROM_FLAT=[yes]" in r.stdout
  assert not (
    moddir.exists() and list(moddir.glob(".tmp.module.*"))
  )  # no staging


def test_import_module_distinct_sources_to_shared_namespace(cmk, tmp_path):
  # Two DIFFERENT modules imported to the SAME destination namespace must BOTH land:
  # the staged file is keyed on <source>-<dest>, so they get distinct tmpfiles
  # instead of colliding on one (which the include-once guard would then dedup-skip).
  moddir = tmp_path / "modules"
  body = (
    "define Alpha\n"
    "afromalpha := A\n"
    "endef\n"
    "define Beta\n"
    "bfrombeta := B\n"
    "endef\n"
    "$(call mk.import.module, def=Alpha namespace=shared)\n"
    "$(call mk.import.module, def=Beta namespace=shared)\n"
    "probe:; @printf 'a=[%s] b=[%s]\\n' '$(shared.afromalpha)' '$(shared.bfrombeta)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "a=[A] b=[B]" in r.stdout  # both modules merged under `shared.`
  keys = sorted(p.name for p in moddir.glob(".tmp.module.*.mk"))
  assert keys == [".tmp.module.Alpha-shared.mk", ".tmp.module.Beta-shared.mk"]


def test_import_module_file_basename_collision_distinct_content(cmk, tmp_path):
  # Two DISTINCT files sharing a basename (foo.cmk) in different dirs must BOTH
  # bind: a file-import's staged key is content-addressed, so they stage to
  # distinct `.tmp.module.foo-<hash>.mk` files instead of the second silently
  # overwriting + dedup-skipping the first.
  moddir = tmp_path / "modules"
  (tmp_path / "a").mkdir()
  (tmp_path / "b").mkdir()
  (tmp_path / "a" / "foo.cmk").write_text("FROMA := A\n")
  (tmp_path / "b" / "foo.cmk").write_text("FROMB := B\n")
  body = (
    "$(call mk.import.module, file=a/foo.cmk flat=1)\n"
    "$(call mk.import.module, file=b/foo.cmk flat=1)\n"
    "probe:; @printf 'a=[%s] b=[%s]\\n' '$(FROMA)' '$(FROMB)'\n"
  )
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
  )
  assert r.ok, r.stderr
  assert "a=[A] b=[B]" in r.stdout  # both bound -- no basename collision
  # same basename, different content -> two distinct content-addressed staged files
  staged = sorted(p.name for p in moddir.glob(".tmp.module.foo-*.mk"))
  assert len(staged) == 2, staged


def test_import_module_self_import_terminates(cmk, tmp_path):
  # A module that imports ITSELF must NOT loop forever -- the include-once guard
  # skips the re-entrant include of the staged copy so the import terminates.
  moddir = tmp_path / "modules"
  body = (
    "define selfmod\n"
    "$(call mk.import.module, def=selfmod)\n"  # re-imports itself
    "selfv := self-ok\n"
    "endef\n"
    "$(call mk.import.module, def=selfmod)\n"
    "probe:; @printf 'selfv=[%s]\\n' '$(selfmod.selfv)'\n"
  )
  # the short timeout is the real assertion: a regression would hang, not fail slow
  r = cmk(
    "probe",
    env={"CMK_MODULES_DIR": str(moddir)},
    makefile=_wrapper(tmp_path, body),
    timeout=45,
  )
  assert r.ok, r.stderr
  assert "selfv=[self-ok]" in r.stdout


def test_include_plugin_dedups_double_import(cmk, tmp_path):
  # The same plugin imported twice is deduped (include-once): the second include is
  # skipped, so there is no `overriding recipe` churn (which recursion would spam).
  _plugin(tmp_path / ".cmk", "dup.mk", "dtgt:; @echo dup-tgt\n")
  body = (
    "$(call mk.include.plugin, dup.mk)\n"
    "$(call mk.include.plugin, dup.mk)\n"  # second time -> skipped
    "probe: dtgt\n"
  )
  r = cmk("probe", makefile=_wrapper(tmp_path, body))
  assert r.ok, r.stderr
  assert "dup-tgt" in r.stdout
  assert "overriding recipe" not in r.stderr  # dedup avoided the re-include
