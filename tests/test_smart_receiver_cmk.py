"""Tests for the SMART receiver + the `open`/`import` namespace directives + the namespace lint.

A namespaced send with an arg/stream/env trailer (`(`/`[`/`{`) lowers to the SMART routing core

    $(if $(filter file override,$(origin NAME)),$(call NAME,ARGS),${make} NAME/STEM)

so a defined MACRO wins (fast, no reparse) else the published TARGET, decided at runtime by
`$(origin)`.  Two directives OPEN a namespace for such unqualified routing, split on INTENT:

  import <ns>  I will USE ns.  Resolves + loads: an already-PRESENT namespace (core like flux, or
               `ns.*` defined) is a no-op, a plugin/module on CMK_PLUGINS_DIR is loaded.  HARD
               ERROR only when the name resolves to nothing.
  open <ns>    I will CONTRIBUTE to ns (define `ns.*` here).  Register-only, NEVER a hard error.

Existence errors fire at the compiled program's LOAD, not at pure transpile.  A compile-time
NAMESPACE LINT (opt-out `CMK_NS_LINT=0`) warns on intent mismatch: import-then-define (pollution),
open-without-defining (pointless), either-without-using (dead).  A separate SHADOW check warns when
a smart send targets a divergent twin; `CMK_SHADOW_STRICT=1` escalates it to a hard failure.
"""

import shutil
from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def smart(name, macro_args="", target_stem="", paren=False):
  # origin-routing smart core; a no-arg paren callform guards its macro branch.
  if macro_args:
    mb = f"$(call {name},{macro_args})"
  elif paren:
    mb = (
      f"$(if $(filter-out undefined,$(origin {name}.__name__)),"
      f"$(error cmk-fault errno=GRAMMAR code=65 :: cmk: {name}() is not callable: "
      f"{name} is a namespace with no .__call__ -- call a member like {name}.x or "
      f"define .__call__),$(call {name}))"
    )
  else:
    mb = f"$(call {name})"
  tb = (
    f"${{make}} {name}/{target_stem}" if target_stem else f"${{make}} {name}"
  )
  inner = f"$(if $(filter file override,$(origin {name})),{mb},{tb})"
  cb = (
    f"$(call {name}.__call__,{macro_args})" if macro_args else f"$(call {name}.__call__)"
  )
  return f"$(if $(filter file override,$(origin {name}.__call__)),{cb},{inner})"


def _run(cmk, tmp_path, src):
  """Compile CMK ``src`` and run its ``__main__`` via plain ``make -f`` (no plugin resolution)."""
  compiled = cmk("mk.compile", stdin=src)
  assert compiled.ok, compiled.stderr
  shutil.copy(COMPOSE_MK, tmp_path / "compose.mk")
  (tmp_path / "out.mk").write_text("include compose.mk\n" + compiled.stdout)
  return cmk("__main__", makefile=str(tmp_path / "out.mk"), cwd=str(tmp_path))


def _interpret(cmk, tmp_path, src, plugins=None, strict=False):
  """Run CMK ``src`` end-to-end via ``mk.interpret!`` with an optional hermetic plugin dir."""
  (tmp_path / "prog.cmk").write_text(src)
  (tmp_path / "plugins").mkdir(exist_ok=True)
  for name, body in (plugins or {}).items():
    (tmp_path / "plugins" / name).write_text(body)
  env = {"CMK_SUPERVISOR": "1", "CMK_PLUGINS_DIR": "plugins"}
  if strict:
    env["CMK_SHADOW_STRICT"] = "1"
  return cmk(
    "mk.interpret!", "prog.cmk", cwd=str(tmp_path), env=env, timeout=120
  )


# --- directive lowering ------------------------------------------------------


def test_open_dissolves_via_module_subkind(ir):
  # `open ns` dissolves through the `module` ambient subkind: no `cmk.open` runtime call
  # (it never errors), just a throwaway def + `ambient.dissolve kind=module` (whose handler
  # is include.plugins).  One unified dissolve seam, shared with `*(| .. |)`.
  r = ir("open reports\nreports.x:; @true\n")
  assert "cmk.open" not in r.stdout
  assert "define __open_" in r.stdout and "reports" in r.stdout
  assert "$(call ambient.dissolve, def=__open_" in r.stdout and "kind=module)" in r.stdout


def test_import_lowers_to_assert_plus_dissolve(ir):
  # `import foo` -> the `cmk.import` assertion AND the `module`-subkind dissolve load.
  r = ir("import foo\nx:\n\tfoo.go()\n")
  assert "$(call cmk.import,foo)" in r.stdout
  assert "$(call ambient.dissolve, def=__open_" in r.stdout and "kind=module)" in r.stdout


def test_import_comma_list_loads_all(ir):
  r = ir("import a, b\nx:\n\ta.go()\n\tb.go()\n")
  assert "$(call cmk.import,a b)" in r.stdout
  # both names land in one throwaway def; module.__open__ foreach-loads each
  assert "define __open_" in r.stdout and "\na b\n" in r.stdout
  assert "kind=module)" in r.stdout


def test_import_makes_ns_smart(ir):
  r = ir("import flux\nx:\n\tflux.ok()\n")
  assert smart("flux.ok", paren=True) in r.stdout


def test_open_inert_inside_define(ir):
  r = ir("define blk\nopen flux\nendef\nx:; @true\n")
  assert "open flux" in r.stdout
  assert "cmk.open" not in r.stdout


def test_dotted_import_sugar_not_a_directive(ir, tmp_path):
  # `import.targets(...)` (dotted, compile-time inline sugar) is not the `import <ns>` directive.
  (tmp_path / "src.mk").write_text("greet:\n\t@echo hi\n")
  r = ir(
    "import.targets(file=src.mk target=greet)\n",
    cwd=str(tmp_path),
  )
  assert "greet:" in r.stdout and "@echo hi" in r.stdout
  assert "cmk.import" not in r.stdout and "cmk.open" not in r.stdout


# --- channel routing over the smart core (import flux = use) ------------------


def test_macro_args_verbatim_target_stem_stripped(ir):
  r = ir("import flux\nx:\n\tflux.pool(4, a, b)\n")
  assert "$(call flux.pool,4, a, b)" in r.stdout  # macro branch: verbatim
  assert "${make} flux.pool/4,a,b" in r.stdout  # target branch: stripped


def test_stream_wraps_smart_core(ir):
  r = ir("import flux\nx:\n\tflux.foo[echo hi]\n")
  assert f"echo hi | {smart('flux.foo')}" in r.stdout


def test_env_wraps_smart_core(ir):
  # the env value passes RAW (no compiler quoting -- see test_callform_cmk.py).
  r = ir("import flux\nx:\n\tflux.bar{e=v}\n")
  assert f"e=v {smart('flux.bar')}" in r.stdout


def test_smart_predicate_method_question_suffix(ir):
  # a predicate suffix joins a method name at the callform position; the send routes smart.
  r = ir("import flux\nx:\n\tflux.ok?(a)\n")
  assert smart("flux.ok?", macro_args="a", target_stem="a") in r.stdout


def test_smart_bang_method_suffix(ir):
  r = ir("import flux\nx:\n\tflux.reset!(a)\n")
  assert smart("flux.reset!", macro_args="a", target_stem="a") in r.stdout


def test_smart_question_assign_not_routed(ir):
  # a conditional-assign in a recipe must not smart-route.
  r = ir("import flux\nx:\n\tflux.foo?=bar\n")
  assert "$(origin flux.foo" not in r.stdout
  assert "flux.foo?=bar" in r.stdout


def test_slash_and_triple_stay_target(cmk):
  r = cmk(
    "mk.compile", stdin="import flux\nx:\n\tflux.foo/a,b\n\tflux.baz'''L'''\n"
  )
  assert r.ok, r.stderr
  assert "${make} flux.foo/a,b" in r.stdout
  assert "${make} flux.baz" in r.stdout
  assert (
    "$(origin flux.foo" not in r.stdout and "$(origin flux.baz" not in r.stdout
  )


def test_this_and_cmk_anchors_unchanged_with_import(ir):
  r = ir(
    "import flux\nx:\n\tthis.foo/a\n\tcmk.log(hi)\n\tflux.ok()\n",
  )
  assert "${make} foo/a" in r.stdout
  assert "$(call log,hi)" in r.stdout
  assert "$(origin foo)" not in r.stdout


# --- runtime routes (import a present namespace; no plugin resolution needed) -


def test_runtime_target_route(cmk, tmp_path):
  # `flux.ok` has no macro twin -> the core routes to `${make} flux.ok` and succeeds.
  r = _run(cmk, tmp_path, "import flux\n__main__:\n\tflux.ok()\n")
  assert r.ok, r.stderr


def test_runtime_macro_route_forwards_args(cmk, ir, tmp_path):
  # `flux.pipe.fork` HAS a macro twin (a trampoline): the core routes to the macro, which now
  # forwards args to the parametric target (the Part-3 hardening).  fan stdin to two echoes.
  src = "import flux\n__main__:\n\techo payload | flux.pipe.fork(stream.echo,stream.echo)\n"
  compiled = ir(src)
  assert "$(call flux.pipe.fork,stream.echo,stream.echo)" in compiled.stdout
  out = _run(cmk, tmp_path, src)
  assert out.ok, out.stderr
  assert out.stdout.count("payload") >= 2


# --- intent / existence semantics (runtime, hermetic) ------------------------


def test_import_present_namespace_is_noop(cmk, tmp_path):
  # `import flux` -- flux is already present (core) -> a no-op USE, not an error.
  r = _interpret(cmk, tmp_path, "import flux\n__main__:\n\tflux.ok()\n")
  assert r.ok, r.stderr


def test_import_loads_plugin_member(cmk, tmp_path):
  # `import foo` loads the hermetic foo.mk plugin, so its `foo.hi` target is callable.
  r = _interpret(
    cmk,
    tmp_path,
    "import foo\n__main__:\n\tfoo.hi()\n",
    plugins={"foo.mk": "foo.hi:\n\t@printf 'PLUGHI\\n'\n"},
  )
  assert r.ok, r.stderr
  assert "PLUGHI" in r.stdout


def test_import_resolving_to_nothing_hard_errors(cmk, tmp_path):
  # `import` of a name that is neither present, loadable, nor loaded is a HARD ERROR.
  r = _interpret(cmk, tmp_path, "import nope_xyz\n__main__:; @true\n")
  assert not r.ok
  assert "errno=IMPORT_NOT_FOUND" in (r.stdout + r.stderr)


def test_open_loads_if_exists(cmk, tmp_path):
  # `open <plugin>` = import + modify-intent: it LOADS the plugin (foo.hi callable) AND lets you
  # extend the namespace (foo.mine).  Never a hard error.
  r = _interpret(
    cmk,
    tmp_path,
    "open foo\n__main__:\n\tfoo.hi()\n\tfoo.mine()\nfoo.mine:\n\t@printf 'OPENOK\\n'\n",
    plugins={"foo.mk": "foo.hi:\n\t@printf 'PLUGHI\\n'\n"},
  )
  assert r.ok, r.stderr
  assert "PLUGHI" in r.stdout  # the plugin was loaded (foo.hi)
  assert "OPENOK" in r.stdout  # + the local extension ran
  assert "CONFLICT" not in (r.stdout + r.stderr)


def test_open_nonexistent_is_register_only(cmk, tmp_path):
  # `open <fresh>` (no file) = pure forward-declaration: no load, no error, populate later.
  r = _interpret(
    cmk,
    tmp_path,
    "open fresh\n__main__:\n\tfresh.hi()\nfresh.hi:\n\t@printf 'FRESH\\n'\n",
  )
  assert r.ok, r.stderr
  assert "FRESH" in r.stdout


def test_open_contribute_runs(cmk, tmp_path):
  # `open ns` + define ns.* + call unqualified.
  r = _run(
    cmk,
    tmp_path,
    "open rep\n__main__:\n\trep.hi()\nrep.hi:\n\t@printf 'REPHI\\n'\n",
  )
  assert r.ok, r.stderr
  assert "REPHI" in r.stdout


# --- namespace lint (intent mismatch, compile-time, soft) --------------------


def test_nslint_dead(ir):
  r = ir("import flux\nx:; @true\n")
  assert "never used or defined" in r.stderr


def test_nslint_pollution(cmk):
  r = cmk(
    "mk.compile", stdin="import flux\nx:\n\tflux.ok()\nflux.mine:; @true\n"
  )
  assert r.ok, r.stderr
  assert "namespace pollution" in r.stderr


def test_nslint_empty_open(ir):
  r = ir("open flux\nx:\n\tflux.ok()\n")
  assert "nothing contributed" in r.stderr


def test_nslint_clean_open_contribute(ir):
  # open + define + call -> no namespace warning.
  r = ir("open rep\nx:\n\trep.hi()\nrep.hi:; @true\n")
  for phrase in (
    "never used or defined",
    "namespace pollution",
    "nothing contributed",
  ):
    assert phrase not in r.stderr


def test_nslint_clean_import_use(ir):
  r = ir("import flux\nx:\n\tflux.ok()\n")
  for phrase in (
    "never used or defined",
    "namespace pollution",
    "nothing contributed",
  ):
    assert phrase not in r.stderr


def test_nslint_clean_predicate_use(ir):
  # a predicate-method use counts as a use, so no false dead-namespace warning.
  r = ir("import flux\nx:\n\tflux.ok?(a)\n")
  assert "never used or defined" not in r.stderr


def test_nslint_clean_import_anchored_use(ir):
  # a cmk.-anchored send registers the namespace as used (the anchor lowers to a
  # sentinel before nslint, so nl_use must see through it -- else a false "dead").
  r = ir("import flux\nx:\n\tcmk.flux.ok()\n")
  assert "never used or defined" not in r.stderr


def test_nslint_optout(cmk):
  r = cmk(
    "mk.compile", stdin="import flux\nx:; @true\n", env={"CMK_NS_LINT": "0"}
  )
  assert r.ok, r.stderr
  assert "never used or defined" not in r.stderr


# --- shadow lint (import flux = use; the send targets a divergent twin) -------


def test_shadow_warns_on_divergent_send(ir):
  r = ir("import flux\nx:\n\tflux.stage.file(s)\n")
  assert "DIVERGENT" in r.stderr and "flux.stage.file" in r.stderr


def test_shadow_no_false_positive(ir):
  r = ir("import flux\nx:\n\tflux.ok()\n")
  assert "DIVERGENT" not in r.stderr


def test_shadow_dedupes(ir):
  r = ir(
    "import io\nx:\n\tio.env(A)\n\tio.env(B)\n\tio.env(C)\n",
  )
  assert r.stderr.count("DIVERGENT") == 1


def test_shadow_strict_fails(cmk, tmp_path):
  r = _interpret(
    cmk,
    tmp_path,
    "import flux\n__main__: x\nx:\n\tflux.stage.file(s)\n",
    strict=True,
  )
  assert not r.ok
  assert "CMK_SHADOW_STRICT" in (r.stdout + r.stderr)


def test_shadow_strict_passes_safe(cmk, tmp_path):
  r = _interpret(
    cmk, tmp_path, "import flux\n__main__:\n\tflux.ok()\n", strict=True
  )
  assert r.ok, r.stderr


# --- the collision lint (host self-consistency) ------------------------------


def test_lint_collisions_passes(cmk):
  r = cmk("lang.lint.self.collisions")
  assert r.ok, r.stdout + r.stderr
  assert "macro/target twins" in r.stderr
