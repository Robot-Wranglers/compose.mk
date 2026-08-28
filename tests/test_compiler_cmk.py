"""Compiler suite (low-hanging fruit): pure CMK->Makefile transforms.

The CMK transpile pipeline (mk.compile, lang.comp.pipeline.*) is local awk/sed -
pure stdin->stdout, no docker. These assert *containment* of key transforms
rather than byte-exact golden output (compiled output carries a context header,
an `__interpreting__=` shebang, and a trailing NUL; golden tests deferred).

Heavier pieces deferred: mk.compile!/mk.interpret (embed/run), curated .cmk/.mk
behavioral twins, and full golden snapshots.
"""

import json
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler


def test_mk_compile_dialect(ir):
  # Default dialect maps `this.` -> `${make} ` across the full pipeline.
  r = ir("x:\n\tthis.y\n")
  assert "${make} y" in r.stdout


def test_mk_preprocess_dialect(cmk):
  r = cmk("lang.comp.pipeline.dialect", stdin="x:\n\tthis.y\n")
  assert r.ok, r.stderr
  assert "${make} y" in r.stdout


# Regression: a per-file custom `cmk_dialect`/`cmk_sugar` arrives as COMPACT JSON --
# every rule on one line.  The jq->awk generator rewrite (_cmk.gen.dialect /
# _cmk.gen.sugar) once emitted a substitution pipe for only the FIRST rule per line
# (the default tables are one-rule-per-line, so it hid), so a multi-rule custom
# dialect silently applied only rule 1 -- `this.` (rule 3) vanished and the demo's
# `this.alice.dispatch(..)` ran as a bogus shell command.  See demos/cmk/user-sugar.cmk.


def test_custom_dialect_applies_every_rule(cmk):
  dialect = '[["cmk.io.","${make} io."],["cmk.","؆"],["this.","${make} "]]'
  r = cmk(
    "lang.comp.pipeline.dialect",
    stdin="x:\n\tthis.y\n\tcmk.io.z\n",
    env={"cmk_dialect": dialect},
  )
  assert r.ok, r.stderr
  assert "${make} y" in r.stdout        # rule 3 (this.) -- the one that used to drop
  assert "${make} io.z" in r.stdout     # rule 1 (cmk.io.)


def test_validate_diagnoser_hints(cmk, tmp_path):
  # mk.validate classifies make's opaque `-n` failure into a FAULT-TYPE name (RuleMissing /
  # SyntaxError -- a namespace for the coming faults/exceptions taxonomy), printed red as the
  # header of the `ERR:` block, ABOVE the raw traceback (preserved verbatim, carrying the
  # token).  A valid file gets neither.
  bad = tmp_path / "bad.mk"
  bad.write_text("foo: no-such-target\n\t@true\n")
  r = cmk("mk.validate/bad.mk", cwd=tmp_path)
  err = r.stderr
  assert r.returncode != 0
  assert "No rule to make target" in err                        # raw traceback preserved
  assert "// ERR:" in err and "RuleMissing:" in err             # the ERR block + fault type
  assert err.index("RuleMissing:") < err.index("No rule to make target")  # type header BEFORE raw

  sep = tmp_path / "sep.mk"
  sep.write_text("foo:\nbar not a valid line\n")
  o2 = cmk("mk.validate/sep.mk", cwd=tmp_path).stderr
  assert "missing separator" in o2 and "SyntaxError:" in o2

  ok = tmp_path / "ok.mk"
  ok.write_text("foo:; @true\n")
  o3 = cmk("mk.validate/ok.mk", cwd=tmp_path).stderr
  assert not any(s in o3 for s in ("// ERR:", "RuleMissing:", "SyntaxError:"))  # no false positive

  # a bad GOAL (validate dry-runs with `goals=`, as mk.interpret passes the CLI continuation)
  # is also RuleMissing; the token lives in the raw traceback.
  r4 = cmk("mk.validate/ok.mk", cwd=tmp_path, env={"goals": "zzzz"})
  o4 = r4.stderr
  assert r4.returncode != 0 and "RuleMissing:" in o4 and "No rule to make target 'zzzz'" in o4


def test_trace_remap_source_map(cmk, tmp_path):
  # The reverse source-mapper (`_awklang_trace_remap`, behind mk.validate's `source:` post-mortem):
  # a dry-run failure blames the compiled temp, meaningless to the author, so a blamed line is
  # traced back to the CMK source via STRUCTURAL, grammar-free anchors -- a `def=NAME` ctor arg, a
  # `define NAME`, or a `NAME:` target header -- plus missing-target names.  Tested in isolation:
  # feed synthetic make-stderr + source + compiled-temp straight to the awk.
  awk = tmp_path / "remap.awk"
  awk.write_text(cmk("mk.get/_awklang_trace_remap").stdout)
  src = tmp_path / "s.cmk"
  src.write_text(
    "import log\n"                    # 1
    "zzzclass Pet[|\n"                # 2  def=Pet -> here
    "  ${self}.speak:; log(hi)\n"     # 3
    "|]\n"                            # 4
    "zebra <- Pet.new()\n"           # 5  missing-rule target -> here
    "deploy:\n"                       # 6  define/target anchor -> here
    "  echo hi\n"                     # 7
  )
  temp = tmp_path / "t.mk"           # a compiled temp: each blamed line names a construct
  temp.write_text(
    "filler\n"                        # 1
    "$(call zzzclass, def=Pet)\n"     # 2  -> def=Pet
    "define deploy\n"                 # 3  -> define
    "endef\n"                         # 4
  )
  err = (
    "run.tmp:2: warning: undefined variable 'zzzclass'\n"
    "run.tmp:3: *** boom\n"
    "make[5]: *** No rule to make target 'zebra.speak'.  Stop.\n"
  )
  out = subprocess.run(
    ["awk", "-v", "tb=run.tmp", "-v", f"src={src}", "-f", str(awk), "/dev/stdin", str(src), str(temp)],
    input=err, text=True, capture_output=True,
  ).stdout
  assert f"{src}:2: in Pet" in out               # def=NAME anchor
  assert f"{src}:6: in deploy" in out            # define NAME anchor
  assert f"{src}:5: target zebra.speak" in out   # missing-rule name -> its declaration

  clean = subprocess.run(  # no blamed refs / no missing rule -> no frames
    ["awk", "-v", "tb=run.tmp", "-v", f"src={src}", "-f", str(awk), "/dev/stdin", str(src), str(temp)],
    input="make: all good\n", text=True, capture_output=True,
  ).stdout
  assert clean.strip() == ""


def test_custom_sugar_applies_every_rule(cmk):
  # Two block-bracket sugar rules; both must lower (`__NAME__` <- the block's name).
  sugar = '[["Ⓐ","Ⓐ","$(call aaa, def=__NAME__)"],["Ⓑ","Ⓑ","$(call bbb, def=__NAME__)"]]'
  r = cmk(
    "lang.comp.pipeline.sugar",
    stdin="Ⓐ one\nx=1\nⒶ\nⒷ two\ny=2\nⒷ\n",
    env={"cmk_sugar": sugar},
  )
  assert r.ok, r.stderr
  assert "$(call aaa, def=one" in r.stdout   # rule 1
  assert "$(call bbb, def=two" in r.stdout   # rule 2 -- used to drop


def test_mk_preprocess_minify_strips_comments(cmk):
  r = cmk("lang.comp.pipeline.minify", stdin="# a comment\nfoo:\n\t@true\n")
  assert r.ok, r.stderr
  assert "# a comment" not in r.stdout
  assert "foo:" in r.stdout


def test_mk_preprocess_decorators_passthrough(cmk):
  # Plain input (no decorators) passes through unchanged.
  r = cmk("lang.comp.pipeline.decorators", stdin="foo:\n\t@true\n")
  assert r.ok, r.stderr
  assert "foo:" in r.stdout


# --- piecewise stage transforms (Stage 5-PRE regression net) -----------------
# The compile pipeline is a chain of independent stages (minify -> decorators ->
# dialect -> sugar -> .awk.main.preprocess -> .awk.dispatch). The tests above +
# below pin each *stage's* transform in isolation via its target, so the planned
# pipeline refactor (Stage 5: macros + fused fast path / flux.pipeline debug
# path) is provably behavior-preserving stage-by-stage -- not just end-to-end.
# All pure stdin->stdout (no docker). Stage boundaries are non-obvious: e.g. `ᐉ`
# and `this.` are *dialect* rules; the generic banana `NAME(| .. |)` lowering is *sugar*.


def test_stage_minify_zips_continuations(cmk):
  # `.awk.zip.linefeeds`: a `\`-continued recipe line is joined into one.
  r = cmk("lang.comp.pipeline.minify", stdin="a:\n\tfoo \\\n\tbar\n")
  assert r.ok, r.stderr
  assert "foo bar" in r.stdout


@pytest.mark.docstring
def test_stage_minify_preserves_docstrings(cmk):
  # `@#` docstring lines now pass THROUGH minify; the leading-vs-mid distinction
  # (keep the docstring, drop mid-recipe annotations) is made later by joinbody.
  r = cmk("lang.comp.pipeline.minify", stdin="x:\n\t@# doc here\n\techo hi\n")
  assert r.ok, r.stderr
  assert "doc here" in r.stdout
  assert "echo hi" in r.stdout


def test_stage_minify_preserves_define_block(cmk):
  # Inside define...endef, line-continuations are NOT zipped (raw block).
  r = cmk(
    "lang.comp.pipeline.minify",
    stdin="define blk\nfoo \\\nbar\nendef\nx:\n\t@true\n",
  )
  assert r.ok, r.stderr
  assert "foo \\\nbar" in r.stdout  # continuation preserved in the block


def test_stage_minify_preserves_nested_define_block(cmk):
  # `.awk.zip.linefeeds` depth-tracks: a NESTED define's inner endef must not
  # re-enable zipping for the rest of the OUTER body (continuation stays raw).
  r = cmk(
    "lang.comp.pipeline.minify",
    stdin="define outer\ndefine inner\ni\nendef\nfoo \\\nbar\nendef\n",
  )
  assert r.ok, r.stderr
  assert "foo \\\nbar" in r.stdout  # not zipped: still inside outer define


def test_stage_decorators_relocate_above_target(cmk):
  # A `@` decorator written ABOVE a target is relocated to be the target's
  # first recipe line (then joinbody chains it with the rest of the body).
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@compose.bind.target(debian)\nt:\n\techo hi\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\tcmk.compose.bind.target(debian)\n\techo hi" in r.stdout


def test_stage_decorators_at_assignment_not_a_decorator(cmk):
  # `@foo = bar` / `@foo := bar` is a LEGAL make assignment (a var literally named `@foo`),
  # NOT a decorator -- the parser skips it (an `=` before any `(`), so it isn't mangled into
  # `cmk.foo = bar()`.  `=` INSIDE parens (a kwarg) is still a decorator.
  for src in ("@foo = bar\nt:\n\techo hi\n", "@foo := bar\nt:\n\techo hi\n"):
    r = cmk("lang.comp.pipeline.decorators", stdin=src)
    assert r.ok, r.stderr
    assert src.splitlines()[0] in r.stdout  # assignment passes through untouched
    assert "cmk." not in r.stdout


def test_stage_decorators_require_adjacent_target(cmk):
  # A blank line between the decorator and the target is rejected.
  r = cmk(
    "lang.comp.pipeline.decorators", stdin="@bind.args(from=json, s)\n\nt:\n\techo hi\n"
  )
  assert not r.ok
  assert "immediately above a target" in r.stderr


def test_stage_decorators_postfix_after_body(cmk):
  # `postfix_mode=&&` relocates the decorator to AFTER the body; the last body
  # line gains a trailing `&&` so joinbody chains `body && decorator`.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(postfix_mode=&&)\nt:\n\techo a\n\techo b\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\techo a\n\techo b &&\n\tcmk.mark()" in r.stdout


def test_stage_decorators_postfix_connectors(cmk):
  # The kwarg value IS the shell connector: `;` (always) and `||` (on failure).
  semi = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(postfix_mode=;)\nt:\n\techo body\n",
  )
  assert semi.ok, semi.stderr
  assert "echo body ;\n\tcmk.mark()" in semi.stdout
  orr = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(postfix_mode=||)\nt:\n\techo body\n",
  )
  assert orr.ok, orr.stderr
  assert "echo body ||\n\tcmk.mark()" in orr.stdout


def test_stage_decorators_postfix_strips_kwarg_from_args(cmk):
  # `postfix_mode` is a compiler directive, stripped before the macro call; the
  # decorator's real args survive untouched.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(realarg, postfix_mode=&&)\nt:\n\techo b\n",
  )
  assert r.ok, r.stderr
  assert "cmk.mark(realarg)" in r.stdout
  assert "postfix_mode" not in r.stdout


def test_stage_decorators_postfix_mixed_with_prefix(cmk):
  # A target may carry both: prefix decorators stay at the head, postfix at the
  # tail (`prefix && body || postfix`).
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@pre(x)\n@post(postfix_mode=||)\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\tcmk.pre(x)\n\techo body ||\n\tcmk.post()" in r.stdout


def test_stage_decorators_postfix_space_indented_body(cmk):
  # Space-indented bodies work too: body lines are re-emitted verbatim (the
  # indent stage normalises them later), only the decorator line gets a tab.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(postfix_mode=;)\nt:\n    echo body\n",
  )
  assert r.ok, r.stderr
  assert "    echo body ;\n\tcmk.mark()" in r.stdout


def test_stage_decorators_postfix_invalid_mode_errors(cmk):
  # An unrecognised connector is a compile error.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="@mark(postfix_mode=foo)\nt:\n\techo b\n",
  )
  assert not r.ok
  assert "postfix_mode must be one of" in r.stderr


def test_stage_decorators_postfix_default_mode(cmk):
  # A `<name>.postfix_mode := <conn>` companion declaration makes a BARE
  # `@<name>` postfix without repeating the kwarg on every use.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="g.postfix_mode := ||\n@g\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "echo body ||\n\tcmk.g()" in r.stdout


def test_stage_decorators_postfix_explicit_overrides_default(cmk):
  # An explicit kwarg still wins over the declared default.
  r = cmk(
    "lang.comp.pipeline.decorators",
    stdin="g.postfix_mode := ||\n@g(postfix_mode=;)\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "echo body ;\n\tcmk.g()" in r.stdout


# --- `@` decorator sigil edge cases -----------------------------------------
# `@` (column 0) is THE decorator sigil; the compiler normalises it to
# `cmk.<name>` directly (dialect then lowers `cmk.`->`؆`->`$(call <name>,..)`),
# gated on `!in_def`.  The relocate/postfix behaviour is pinned by the tests above.
# These pin what is UNIQUE to `@`: it is ignored everywhere it is not a column-0 cmk
# decorator (recipe silent-prefix, inline, an assignment, and -- crucially -- embedded
# foreign source such as Python inside a `define`).  See `.awk.decorators`.


def test_stage_decorators_at_bare_name_gets_parens(cmk):
  # A bare `@name` (no args) is normalised + `()`-completed.
  r = cmk("lang.comp.pipeline.decorators", stdin="@fault.guarded\nt:\n\techo hi\n")
  assert r.ok, r.stderr
  assert "cmk.fault.guarded()" in r.stdout


def test_stage_decorators_at_recipe_prefix_untouched(cmk):
  # A TAB-indented `@echo` (make's silent-recipe prefix) is NOT a decorator --
  # only column-0 `@` is.  No false normalisation to `cmk.`.
  r = cmk("lang.comp.pipeline.decorators", stdin="t:\n\t@echo hi\n\t@printf x\n")
  assert r.ok, r.stderr
  assert "\t@echo hi" in r.stdout
  assert "cmk." not in r.stdout


def test_stage_decorators_at_inline_passes_through(cmk):
  # Inline `@` (not column 0) is ambiguous (could be a prereq/recipe token), so it
  # passes through untouched -- only a column-0 `@` is a decorator.
  r = cmk("lang.comp.pipeline.decorators", stdin="t: @notdecorator\n\techo hi\n")
  assert r.ok, r.stderr
  assert "@notdecorator" in r.stdout
  assert "cmk." not in r.stdout


def test_stage_decorators_at_ignored_in_define(cmk):
  # THE key case: a `define` holding EMBEDDED PYTHON with `@`-decorators
  # (@staticmethod, @app.route(...)) must pass through VERBATIM.  The `!in_def`
  # gate means no column-0 `@` inside define..endef is ever treated as a cmk
  # decorator -- otherwise any foreign source (python/js/...) would be corrupted.
  src = (
    "define pysrc\n"
    "@staticmethod\n"
    "def f():\n"
    "    return 1\n"
    "@app.route('/x', methods=['GET'])\n"
    "def g():\n"
    "    return 2\n"
    "endef\n"
    "t:\n\t@true\n"
  )
  r = cmk("lang.comp.pipeline.decorators", stdin=src)
  assert r.ok, r.stderr
  assert "@staticmethod" in r.stdout  # NOT -> cmk.staticmethod
  assert "@app.route('/x', methods=['GET'])" in r.stdout  # NOT rewritten
  assert "cmk." not in r.stdout  # nothing normalised inside the define


def test_stage_dialect_glyph_substitutions(cmk):
  # Default dialect maps the inline glyphs (ᐉ -> .dispatch/, 🡄 -> ${jb}).
  r = cmk("lang.comp.pipeline.dialect", stdin="r: svcᐉt\ne:\n\t🡄 k=v\n")
  assert r.ok, r.stderr
  assert "svc.dispatch/t" in r.stdout
  assert "${jb} k=v" in r.stdout


def test_stage_dialect_custom_hint(cmk):
  # A custom dialect (as would come from a `# cmk_dialect ::: … :::` header,
  # surfaced via the cmk_dialect env) replaces tokens outside define blocks.
  r = cmk(
    "lang.comp.pipeline.dialect",
    stdin="x:\n\tfoo\n",
    env={"cmk_dialect": '[["foo","BAZ"]]'},
  )
  assert r.ok, r.stderr
  assert "BAZ" in r.stdout


def test_stage_dialect_preserves_define_block(cmk):
  # Glyphs inside define...endef are NOT rewritten; only outside.
  r = cmk(
    "lang.comp.pipeline.dialect",
    stdin="define blk\nthis.literal\nendef\nx:\n\tthis.y\n",
  )
  assert r.ok, r.stderr
  assert "this.literal" in r.stdout  # inside: preserved
  assert "${make} y" in r.stdout  # outside: expanded


def test_stage_sugar_block_lowering(cmk):
  # Sugar lowers the generic banana `compose.import.string mylib(| .. |)` to a define
  # plus the `$(call compose.import.string, def=mylib)` prefix-constructor call.
  r = cmk(
    "lang.comp.pipeline.sugar",
    stdin="compose.import.string mylib(|\nservices: {}\n|)\n",
  )
  assert r.ok, r.stderr
  assert "compose.import.string" in r.stdout and "def=mylib" in r.stdout


def test_stage_parse_dialect_hint(cmk):
  # The dialect-hint parser extracts the `:::`-delimited JSON from the header.
  r = cmk(
    ".mk.parse.dialect.hint",
    stdin='# cmk_dialect ::: [["a","b"]] :::\nx:\n',
  )
  assert r.ok, r.stderr
  assert '[["a","b"]]' in r.stdout


def test_stage_parse_sugar_hint(cmk):
  # The sugar-hint parser extracts its `:::`-delimited JSON triples.
  r = cmk(
    ".mk.parse.sugar.hint",
    stdin='# cmk_sugar ::: [["a","b","c"]] :::\nx:\n',
  )
  assert r.ok, r.stderr
  assert '[["a","b","c"]]' in r.stdout


# --- interpreter -------------------------------------------------------------
# `mk.interpret!` ends with mk.yield -> mk.interrupt, a SIGINT-based control
# transfer to the supervisor the standalone shebang installs. Works headless
# *only* with CMK_SUPERVISOR=1 (the harness defaults to 0, where the yield
# epilogue exits nonzero); even then each run costs ~7.5s and installs a real
# signal supervisor. `test_interpret_entrypoint_supervisor` below covers that
# real path once.
#
# The rest exercise the same two steps mk.interpret! does -- `mk.compile` (pure
# awk/sed) then run -- minus the yield, for speed and determinism. The compiled
# output references ${make}/${jq}/${jb} but only declares
# `MAKEFILE_LIST+=compose.mk` (it expects to be *interpreted* by ./compose.mk);
# prepending a real `include compose.mk` makes it runnable by plain `make -f`,
# with ${make} recursion staying inside the compiled file. `project` supplies
# the compose.mk copy the include resolves against. The jb (structured-IO) is
# containerized, so it's gated on docker.


def _run_cmk(ir, project, src):
  """Compile CMK ``src`` and run its ``__main__`` via plain ``make``."""
  compiled = ir(src)
  project.seed_compose_mk()
  project.write("out.mk", "include compose.mk\n" + compiled.stdout)
  return project.run("__main__", makefile="out.mk")


def test_interpret_entrypoint_supervisor(project):
  # End-to-end: drive the *real* `mk.interpret!` shebang entrypoint, exercising
  # compile + yield + the SIGINT supervisor. The harness defaults to
  # CMK_SUPERVISOR=0 (no signal/process-tree magic in the runner); under that
  # setting mk.interpret!'s yield-epilogue can't transfer control and exits
  # nonzero. With CMK_SUPERVISOR=1 the standalone wrapper installs a supervisor
  # and it completes headless -- safe because docker_cmk runs it in its own
  # session (start_new_session), so the supervisor's kill stays scoped.
  project.seed_compose_mk()
  project.write(
    "chain.cmk",
    "a:\n\tprintf one\nb:\n\tprintf two\n__main__:\n\tthis.a; this.b\n",
  )
  r = project.run(
    "mk.interpret!", "chain.cmk", env={"CMK_SUPERVISOR": "1"}, timeout=60
  )
  assert r.ok, r.stderr
  assert "one" in r.stdout and "two" in r.stdout


def test_interpret_dialect_chain(ir, project):
  # `this.<t>` (dialect for `${make} <t>`) drives a multi-target run.
  r = _run_cmk(
    ir,
    project,
    "a:\n\tprintf one\nb:\n\tprintf two\n__main__:\n\tthis.a; this.b\n",
  )
  assert r.ok, r.stderr
  assert "one" in r.stdout and "two" in r.stdout


def test_interpret_jq_extract(ir, project):
  # `🡆` (dialect for `${stream.stdin} | ${jq} -r`) extracts a key. Pure (jq).
  r = _run_cmk(
    ir,
    project,
    "consume:\n\t🡆 .key\n"
    '__main__:\n\techo \'{"key":"VALUE-X"}\' | this.consume\n',
  )
  assert r.ok, r.stderr
  assert "VALUE-X" in r.stdout


@pytest.mark.needs_docker
def test_interpret_structured_io_jb(ir, project):
  # Full structured-IO: `🡄`(jb, containerized) emits JSON, `🡆`(jq) reads it.
  r = _run_cmk(
    ir,
    project,
    "emit:\n\t🡄 key=val\nconsume:\n\t🡆 .key\n"
    "__main__:\n\tthis.emit | this.consume\n",
  )
  assert r.ok, r.stderr
  assert "val" in r.stdout


# --- functional idioms: pure (compile + run __main__, no docker) -------------
# More CMK idioms exercised end-to-end via _run_cmk. Inspired by demos/cmk/*
# (this./jq/host-script/code-import/decorators); all headless, no docker.


def test_interpret_this_with_arg(ir, project):
  # `this.<t>/<arg>` dispatches a pattern target with a parameter.
  r = _run_cmk(
    ir,
    project,
    'greet/%:\n\tprintf "hi $*"\n__main__:\n\tthis.greet/world\n',
  )
  assert r.ok, r.stderr
  assert "hi world" in r.stdout


def test_interpret_jq_nested(ir, project):
  # `🡆 .a.b` extracts a nested key (dialect -> stream.stdin | jq -r).
  r = _run_cmk(
    ir,
    project,
    "consume:\n\t🡆 .a.b\n"
    '__main__:\n\techo \'{"a":{"b":"DEEP"}}\' | this.consume\n',
  )
  assert r.ok, r.stderr
  assert "DEEP" in r.stdout


def test_interpret_host_script_import(ir, project):
  # host.native.bash.polyglot binds a code-block to the core host bash machine,
  # scaffolding a same-named host target (host-native-bash idiom); runs
  # locally, no container.
  r = _run_cmk(
    ir,
    project,
    "host.native.bash.polyglot script.sh(|\n"
    'printf "SCRIPT-RAN\\n"\n'
    "|)\n"
    "__main__: script.sh\n",
  )
  assert r.ok, r.stderr
  assert "SCRIPT-RAN" in r.stdout


def test_interpret_code_block_to_file(ir, project):
  # `code.unbound <name>(| .. |)` (an unbound code-object) yields a generated
  # `<name>.to.file/<f>` that writes the code-block to a file. Pure.
  r = _run_cmk(
    ir,
    project,
    "code.unbound mycode(|\nLINE-IN-CODE\n|)\n__main__:\n\tthis.mycode.to.file/out.txt\n",
  )
  assert r.ok, r.stderr
  assert "LINE-IN-CODE" in (project.dir / "out.txt").read_text()


def test_interpret_call_sugar(ir, project):
  # `cmk.x(args)` lowers to `$(call x,args)`; cmk.log logs the marker.
  r = _run_cmk(ir, project, "__main__:\n\tcmk.log(MARKER-LOG)\n")
  assert r.ok, r.stderr
  assert "MARKER-LOG" in r.stdout + r.stderr


def test_interpret_comments_minified(ir, project):
  # Comments are stripped by minify; the program still runs.
  r = _run_cmk(
    ir,
    project,
    "# a comment\n# another\na:\n\tprintf one\n__main__:\n\tthis.a\n",
  )
  assert r.ok, r.stderr
  assert "one" in r.stdout


def test_interpret_decorator_bind_args_from_json(ir, project):
  # `@bind.args(from=json, ..)` ABOVE a target: parse JSON stdin into vars, filling
  # defaults for absent keys (kwarg-parsing idiom). The recipe body is TWO lines
  # and BOTH must see the bound vars -- i.e. the decorator + body share one shell
  # (the multi-line bug the above-form + joinbody fixes).
  src = (
    "@bind.args(from=json, shape color=blue name=default)\n"
    "consume:\n"
    '\tprintf "1:shape=$${shape} color=$${color}\\n"\n'
    '\tprintf "2:name=$${name}\\n"\n'
    '__main__:\n\techo \'{"shape":"triangle"}\' | this.consume\n'
  )
  r = _run_cmk(ir, project, src)
  assert r.ok, r.stderr
  assert "1:shape=triangle color=blue" in r.stdout
  assert (
    "2:name=default" in r.stdout
  )  # 2nd recipe line also sees the bound var


# --- functional idioms: transpilation of sugar blocks / glyphs (compile-only)
# These idioms need heavy interpreters/containers to *run*, so we assert the
# (pure, deterministic) transpilation instead -- the language-level behavior.


def test_compile_sugar_compose_string(cmk):
  r = cmk(
    "mk.compile", stdin="compose.import.string mylib(|\nservices: {}\n|)\n"
  )
  assert r.ok, r.stderr
  assert "define mylib" in r.stdout
  assert "$(call compose.import.string, def=mylib)" in r.stdout


# The `with .. as ..` runtime trailer and the `docker_context`/`compose_context`
# macros were REMOVED.  Its capability -- run a body in a container/service -- is now
# the `(| body |) in container(| img=.. entrypoint=.. |)` machine-algebra form, and a
# leftover `as`/`as!` clause is a generic postfix error.  These adapt the old
# trailer-parser tests onto those two surfaces.
def test_compile_in_container_inline(ir):
  # `(| body |) in container(| img=.. entrypoint=.. |)` mints an anonymous ambient:
  # the ctor body hoists to `define __ambient_N`, `$(call container, def=__ambient_N)`
  # to module scope, and the lambda dispatches into it by name.
  r = ir(
    "open cmk\nscr:\n\t(| echo hi |) in container(| img=alpine entrypoint=sh |)\n",
  )
  assert "define __ambient_" in r.stdout
  assert "img=alpine entrypoint=sh" in r.stdout
  assert "$(call container, def=__ambient_" in r.stdout
  assert "${make} $(call _cmk.host.machine,__ambient_" in r.stdout


def test_compile_trailing_as_errors(ir):
  # the `as C` clause is gone: the `as` word is swept into the postfix-treatment
  # list and fails as an unknown target (a generic postfix error).
  r = ir("scr(|\necho hi\n|) as compose.import.string\n")
  assert "$(error" in r.stdout
  assert "postfix treatment" in r.stdout and "unknown target" in r.stdout


def test_compile_trailing_bang_as_errors(ir):
  # the runtime `as! C` clause is gone too -- same generic postfix error.
  r = ir("scr(|\necho hi\n|) as! compose.import.string\n")
  assert "$(error" in r.stdout
  assert "postfix treatment" in r.stdout and "unknown target" in r.stdout


def test_compile_two_in_container_bananas(ir):
  # back-to-back in-container lambdas each mint their OWN anonymous ambient (the
  # state machine keeps them distinct -- two defines, two ctor calls).
  r = ir(
    (
      "open cmk\n"
      "a:\n\t(| echo hi |) in container(| img=alpine entrypoint=sh |)\n"
      "b:\n\t(| echo bye |) in container(| img=debian entrypoint=sh |)\n"
    ),
  )
  assert r.stdout.count("define __ambient_") == 2
  assert r.stdout.count("$(call container, def=__ambient_") == 2


# A module is no longer a dedicated `⦖ .. ⦕` glyph: it is a generic cooked banana `NAME[| .. |]`
# (lowering to a dedented, reusable `define NAME`) consumed by an explicit `import.module(def=NAME
# [namespace=] [preprocs=])`.  These four adapt the old `⦖`-sugar tests onto that surface.
def test_compile_module_banana_define(ir):
  # `NAME[| body |]` lowers the body to a reusable `define NAME .. endef`.
  r = ir("mymod[|\n  FOO := 1\n|]\n")
  assert "define mymod" in r.stdout and "endef" in r.stdout


@pytest.mark.xfail(
  strict=True,
  reason="TODO: banana delimiter matching is not enforced.  The OPEN char alone selects the frame's "
  "cook/raw treatment (BTREAT[<open>]) and bclose() accepts any of `|)`/`|]`/`|}`, so a block opened "
  "with `(|` may be closed with `|]` (or `[|` with `|)`) and it lowers as if matched -- surfaced by "
  "demos/cmk/tier-2.cmk (a `(| .. |]` Pet class that compiles today).  A mismatched open/close pair "
  "should be a compile error.  If this xpasses, the banana stage learned to check the closer against "
  "the opener -- keep the check and drop this marker.",
)
def test_banana_bracket_mismatch_is_rejected(ir):
  # `(|` opened but `|]` closed -- a delimiter mismatch that today lowers silently as if matched.
  r = ir("from cmk import class\nclass Foo(|\n  ${self}.speak:; log(hi)\n|]\n", ok=False)
  assert not r.ok or "cmk:" in r.stdout


@pytest.mark.docstring
def test_compile_module_banana_docstring(ir):
  # A `'''docstring'''` first line inside a banana body lifts to a sibling `<name>.__doc__`
  # define keyed on the banana's lexical name (here `mymod.__doc__`), never landing in the
  # shape (exercised end-to-end by module-system.cmk).
  r = ir("mymod[|\n  '''the doc'''\n  greet:; x\n|]\n")
  assert "define mymod" in r.stdout
  assert "mymod.__doc__" in r.stdout and "the doc" in r.stdout


def test_compile_module_banana_indented_dedents(ir):
  # The body may be written indented for visual nesting: the `dedent` stage strips the first
  # body line's prefix uniformly, so the target lands at col 0 inside the define (not a stray
  # tab recipe), identically to a col-0-body module.
  indented = ir("mymod[|\n\tgreet:; x\n|]\n")
  col0 = ir("mymod[|\ngreet:; x\n|]\n")
  assert indented.ok, indented.stderr
  assert col0.ok, col0.stderr
  assert indented.stdout == col0.stdout
  assert "define mymod" in indented.stdout
  assert "\ngreet:" in indented.stdout and "\n\tgreet:" not in indented.stdout


def test_compile_module_banana_inconsistent_indent_warns(ir):
  # A body line less-indented than the first is INCONSISTENT: the dedent stage warns (naming the
  # block) and passes it through verbatim; compile still proceeds.
  r = ir("mymod[|\n\t\tgreet:; x\n\tsvc:; y\n|]\n")
  assert "cmk:dedent" in r.stderr and "mymod" in r.stderr
  assert r.ok, r.stderr


def test_dedent_indented_preserves_internal(cmk):
  # An indented block body dedents to col 0, but deeper INTERNAL indentation (a python loop
  # body, whitespace-significant) is preserved -- indented and col-0 forms dedent identically.
  # (Uses a generic banana `NAME(| .. |)` -- what the dedent stage now operates on.)
  indented = cmk(
    "lang.comp.pipeline.dedent",
    stdin="s_py(|\n    import sys\n    for x in [1]:\n        print(x)\n|)\n",
  )
  col0 = cmk(
    "lang.comp.pipeline.dedent",
    stdin="s_py(|\nimport sys\nfor x in [1]:\n    print(x)\n|)\n",
  )
  assert indented.ok, indented.stderr
  assert col0.ok, col0.stderr
  assert indented.stdout == col0.stdout
  assert "\nimport sys" in indented.stdout and "\n    import sys" not in indented.stdout
  assert "\n    print(x)" in indented.stdout


def test_dedent_two_bananas_no_swallow(cmk):
  # Two adjacent bananas `NAME(| .. |)` must dedent independently -- the state
  # machine closes each on its own `|)` and does not swallow the following block.
  r = cmk(
    "lang.comp.pipeline.dedent", stdin="a(|\n  x\n|)\nb(|\n  y\n|)\n"
  )
  assert r.ok, r.stderr
  assert "\nx\n" in r.stdout and "\ny\n" in r.stdout
  assert "a(|" in r.stdout and "b(|" in r.stdout


def test_dedent_banana_indented(cmk):
  # A generic banana body dedents its uniform first-level indent to col 0.
  tgt = cmk(
    "lang.comp.pipeline.dedent", stdin="s_sh(|\n    echo hi\n|)\n"
  )
  assert tgt.ok, tgt.stderr
  assert "\necho hi\n" in tgt.stdout and "\n    echo hi\n" not in tgt.stdout


def test_dedent_banana_preserves_nested_content(cmk):
  # A banana carrying data whose internal (deeper) indentation is literal content
  # (e.g. inlined compose YAML) keeps that nesting: the uniform first-level indent
  # is stripped, but the deeper `b: 1` stays indented relative to `a:`.
  r = cmk(
    "lang.comp.pipeline.dedent",
    stdin="compose.import.string svc(|\n  a:\n    b: 1\n|)\n",
  )
  assert r.ok, r.stderr
  assert "\na:\n" in r.stdout and "\n  b: 1\n" in r.stdout


def test_dedent_code_inconsistent_indent_warns(cmk):
  # A body line less-indented than the first is INCONSISTENT: warn (naming the block) and
  # pass the whole block through verbatim.  Non-fatal (matches module behavior).
  r = cmk("lang.comp.pipeline.dedent", stdin="s_py(|\n\t\timport sys\n\tx=1\n|)\n")
  assert "cmk:dedent" in r.stderr and "s_py" in r.stderr
  assert r.ok, r.stderr


def test_compile_dispatch_glyph_and_call(ir):
  # `ᐉ` and `.dispatch(x)` both lower to `.dispatch/x`.
  assert (
    "svc.dispatch/target"
    in ir("run: svcᐉtarget\n").stdout
  )
  assert (
    "svc.dispatch/target"
    in ir("run: svc.dispatch(target)\n").stdout
  )


def test_compile_decorator(ir):
  # `@<deco>(args)` above a target -> `cmk.<deco>` -> `$(call bind.<deco>,args)`
  # as the target's first recipe line.
  r = ir("@compose.bind.target(debian)\nt:\n")
  assert "$(call compose.bind.target,debian)" in r.stdout


def test_compile_decorator_log_target(ir):
  # `log` lets log be a decorator (with a message).
  r = ir("@log(starting)\nt:\n\tcmd\n")
  assert "$(call log,starting)" in r.stdout


def test_compile_decorator_bare_no_parens(ir):
  # A bare decorator (no `()`) behaves like an empty call: both lower the same.
  bare = ir("@log\nt:\n\tcmd\n")
  empty = ir("@log()\nt:\n\tcmd\n")
  assert bare.ok and empty.ok, bare.stderr
  assert "$(call log,)" in bare.stdout
  assert "$(call log,)" in empty.stdout


def test_interpret_decorator_log_target(ir, project):
  # log as a decorator: it logs (stderr) and returns 0, so the body runs.
  src = (
    "@log(starting)\n"
    "build:\n\tprintf 'BODY1\\n'\n\tprintf 'BODY2\\n'\n"
    "__main__: build\n"
  )
  r = _run_cmk(ir, project, src)
  assert r.ok, r.stderr
  assert (
    "BODY1" in r.stdout and "BODY2" in r.stdout
  )  # decorator returned 0; body ran
  assert "starting" in (r.stdout + r.stderr)  # the message was logged


def test_compile_call_sugar(ir):
  r = ir("compose.import(file=x.yml)\n")
  assert "$(call compose.import" in r.stdout and "file=x.yml" in r.stdout


def test_compile_import_sugar_docker_import(cmk):
  # `docker.import` is an import-shorthand too, so a bare module-level call lowers to
  # `$(call ..)` -- same as the `code`/`compose.import` family.  Backs demos/cmk/docker.import.cmk.
  r = cmk(
    "mk.compile", stdin="docker.import(namespace=debian img=debian/buildd)\n"
  )
  assert r.ok, r.stderr
  assert "$(call docker.import,namespace=debian img=debian/buildd)" in r.stdout


# --- docker.import codegen (parse-time, docker-free) ------------------------
# These pin the make state `docker.import` *generates* (the `<ns>.img` / build /
# dispatch / run family), not the transpile lowering above.  A wrapper makefile
# `include`s compose.mk and expands `$(call docker.import, ..)` at parse time --
# no image is ever built, so no docker is needed.  CMK_INTERNAL=0 so the codegen
# branch (the `else` of the CMK_INTERNAL guard in the body) actually fires.

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"


def _docker_import_img(cmk, tmp_path, args, ns, dockerfile=True):
  # Expand `$(call docker.import, <args>)` and read back the generated `<ns>.img`.
  body = f"include {COMPOSE_MK}\n"
  if dockerfile:
    body += "define Dockerfile.mytool\nFROM alpine\nendef\n"
  body += f"$(call docker.import, {args})\n"
  body += f"probe:; @printf '%s' \"$({ns}.img)\"\n"
  mk = tmp_path / "Makefile"
  mk.write_text(body)
  r = cmk("probe", makefile=mk, cwd=tmp_path, env={"CMK_INTERNAL": "0"})
  assert r.ok, r.stderr
  return r.stdout.strip()


def test_docker_import_def_namespace_defaults_to_image(cmk, tmp_path):
  # `def=Dockerfile.<X>` with no namespace: the namespace defaults to the image
  # name (`<X>` = the def minus the `Dockerfile.` prefix) and `<X>.img` is
  # `compose.mk:<X>`.  Pins the batch-`mk.unpack.kwargs` default in
  # `_docker.import.def` (`namespace=$${img_name}`).
  got = _docker_import_img(cmk, tmp_path, "def=Dockerfile.mytool", "mytool")
  assert got == "compose.mk:mytool"


def test_docker_import_def_namespace_override(cmk, tmp_path):
  # An explicit `namespace=` names the target family, but the image name still
  # derives from the def (`Dockerfile.mytool` -> `compose.mk:mytool`), independent
  # of the namespace.
  got = _docker_import_img(
    cmk, tmp_path, "def=Dockerfile.mytool namespace=custom", "custom"
  )
  assert got == "compose.mk:mytool"


def test_docker_import_stock_image_passthrough(cmk, tmp_path):
  # The no-def/no-file form (a stock image): `img=` passes through verbatim as the
  # namespace's `.img` (nothing is built).  Blessed demo form
  # `docker.import(namespace=debian img=debian/buildd:bookworm)`.
  got = _docker_import_img(
    cmk,
    tmp_path,
    "namespace=debian img=debian/buildd:bookworm",
    "debian",
    dockerfile=False,
  )
  assert got == "debian/buildd:bookworm"


def test_docker_import_file_default_image(cmk, tmp_path):
  # The `file=<path>` build form with no explicit `img=`: the image name defaults
  # to `compose.mk:<namespace>`.
  got = _docker_import_img(
    cmk,
    tmp_path,
    "namespace=mycontainer file=Dockerfile.x",
    "mycontainer",
    dockerfile=False,
  )
  assert got == "compose.mk:mycontainer"


def test_compile_call_sugar_nested(ir):
  # the generic `cmk.NAME(args)` lowering (.awk.cmk.call) recurses on balanced args.
  r = ir("x:\n\tcmk.a(cmk.b(z))\n")
  assert "$(call a,$(call b,z))" in r.stdout


def test_compile_call_sugar_balanced_inner_parens(ir):
  # inner `(`/`)` that are NOT a call are spanned as ordinary balanced text.
  r = ir("x:\n\tcmk.a(f(1,2))\n")
  assert "$(call a,f(1,2))" in r.stdout


def test_compile_call_sugar_no_paren_fallback(ir):
  # `cmk.NAME` with no immediately-following `(` is left verbatim (not a call).
  r = ir("x:; cmk.foo bar baz\n")
  assert "cmk.foo bar baz" in r.stdout
  assert "$(call foo" not in r.stdout


def test_compile_import_sugar_longest_match(ir):
  # the import-name sugar (.awk.cmk.imports) must longest-match, so
  # `compose.import.string(` lowers as that name -- not `compose.import` + `.string(`.
  r = ir("x:\n\tcompose.import.string(k=1)\n")
  assert "$(call compose.import.string,k=1)" in r.stdout


def test_compile_import_sugar_unbalanced_paren_verbatim(cmk):
  # .awk.cmk.lower fallback: a trigger with an unbalanced `(` is re-emitted
  # verbatim (no partial `$(call ...)`), at the stage level.
  r = cmk("lang.comp.pipeline.imports", stdin="x:; compose.import(a, b\n")
  assert r.ok, r.stderr
  assert "compose.import(a, b" in r.stdout
  assert "$(call" not in r.stdout


def test_imports_sugar_inert_in_nested_define(cmk):
  # .awk.cmk.defskip depth-tracks, so a NESTED define's body passes through
  # verbatim -- the inner endef must NOT prematurely re-enable sugar lowering.
  src = (
    "top:; compose.import(z)\n"
    "define outer\ndefine inner\nX\nendef\ncompose.import(b)\nendef\n"
  )
  r = cmk("lang.comp.pipeline.imports", stdin=src)
  assert r.ok, r.stderr
  assert "$(call compose.import,z)" in r.stdout  # top-level: lowered
  assert "compose.import(b)" in r.stdout  # inside nested define: verbatim
  assert "$(call compose.import,b)" not in r.stdout


def test_compile_inlines_import_target(ir, tmp_path):
  # `import.target(s)(..)` is resolved + INLINED at compile-time (the block is
  # baked into the output), not deferred to a runtime `$(call import.*)`.
  (tmp_path / "src.mk").write_text("greet:\n\t@echo hi\n")
  r = ir("import.targets(file=src.mk target=greet)\n")
  assert "$(call import" not in r.stdout  # not deferred to runtime
  assert "greet:" in r.stdout  # block inlined verbatim
  assert "@echo hi" in r.stdout


def test_compile_inlines_import_def(ir, tmp_path):
  # likewise for define-blocks: inlined as a fresh `define ... endef`.  (The def
  # source must `include compose.mk` -- the importer reads via `mk.def.read`.)
  from pathlib import Path

  compose_mk = Path(__file__).resolve().parent.parent / "compose.mk"
  (tmp_path / "src.mk").write_text(
    f"include {compose_mk}\ndefine greeting\nhello world\nendef\n"
  )
  r = ir("import.def(file=src.mk def=greeting)\n")
  assert "$(call import" not in r.stdout
  assert "define greeting" in r.stdout
  assert "hello world" in r.stdout


def test_compile_jb_glyph(ir):
  assert "${jb}" in ir("e:\n\t🡄 k=v\n").stdout


def test_compile_dialect_preserves_define_block(ir):
  # Glyphs inside define...endef are NOT rewritten -- only outside.
  r = ir(
    "define blk\nthis.literal\nendef\nx:\n\tthis.y\n",
  )
  assert "${make} y" in r.stdout  # outside the block: expanded
  assert "this.literal" in r.stdout  # inside the block: preserved


# --- the `<-` CAPTURE operator ----------------------------------------------
# `LHS <- RHS` captures RHS's output into LHS.  RECIPE (tab-indented) -> shell
# capture ``LHS=`RHS` ``; MODULE (column 0) -> make capture `LHS := $(shell RHS)`.
# `LHS` is a bare identifier at a statement boundary; the `<-` arrow is ADJACENT;
# spacing around it is free.  Runs after the call stage (`this.y` is already
# `${make} y` under mk.compile).  See compose.mk `.awk.cmk.capture`.


def test_compile_capture_recipe_shell(ir):
  # In a recipe (tab-indented), `<-` lowers to a shell backtick capture.
  r = ir("t:\n\tx <- this.y\n")
  assert "x=`${make} y`" in r.stdout


def test_compile_capture_module_shell_func(ir):
  # At MODULE scope (column 0), `<-` lowers to a parse-time `$(shell ...)` capture.
  r = ir("X <- this.y\n")
  assert "X := $(shell ${make} y)" in r.stdout


def test_compile_capture_spacing_is_free(ir):
  # `x<-this.y` (no spaces) == `x <- this.y`.
  r = ir("t:\n\tx<-this.y\n")
  assert "x=`${make} y`" in r.stdout


def test_compile_capture_leaves_tail_intact(ir):
  # capture stops at the `;`; the rest of the line is preserved.
  r = ir("t:\n\tx <- this.y ; echo done\n")
  assert "x=`${make} y" in r.stdout and "`; echo done" in r.stdout


def test_compile_capture_multiple_per_line(ir):
  r = ir("t:\n\ty <- this.a; x <- this.b\n")
  assert "y=`${make} a`; x=`${make} b`" in r.stdout


def test_compile_capture_stops_at_logical_and(ir):
  # `&&` terminates the captured command (the common `x=`cmd` && more` shape).
  r = ir("t:\n\tbody <- ${jq} . && more\n")
  assert "body=`${jq} ." in r.stdout and "`&& more" in r.stdout


def test_compile_capture_stops_at_logical_or(ir):
  # `||` is the third separator and, like `;`/`&&`, closes the capture at top level:
  # `n <- cmd || echo 0` -> ``n=`cmd`|| echo 0`` (the fallback lands after the
  # backticks).  To keep the fallback inside the value, group it (see the brace test).
  r = ir("t:\n\tn <- ${jq} length f || echo 0\n")
  assert "n=`${jq} length f`" in r.stdout and "`|| echo 0" in r.stdout


def test_compile_capture_separator_in_quotes_is_not_a_terminator(ir):
  # a separator inside single or double quotes is part of the command, not a
  # terminator: the whole quoted string is captured.
  r = ir('t:\n\tx <- echo "a; b || c"\n')
  assert 'x=`echo "a; b || c"`' in r.stdout
  s = ir("t:\n\ty <- echo 'p && q'\n")
  assert "y=`echo 'p && q'`" in s.stdout


def test_compile_capture_separator_in_group_is_not_a_terminator(ir):
  # separators inside a `{..}`/`(..)` group are part of the command; the group
  # (and any trailing redirect) is captured whole.  A top-level separator after
  # the group still terminates.
  r = ir("t:\n\tv <- { [ -s f ] && cat f; } 2>/dev/null\n")
  assert "v=`{ [ -s f ] && cat f; } 2>/dev/null`" in r.stdout
  s = ir("t:\n\tw <- { cat f; } || echo none\n")
  assert "w=`{ cat f; }`" in s.stdout and "`|| echo none" in s.stdout


def test_compile_capture_pipeline(ir):
  # A single `|` is NOT a separator (only `;`/`&&`/`||`), so a whole pipeline is
  # captured: `x <- this.one | this.two` -> ``x=`${make} one | ${make} two` ``.
  r = ir("t:\n\tx <- this.one | this.two\n")
  assert "x=`${make} one | ${make} two`" in r.stdout


def test_compile_capture_skips_define_block(ir):
  # `<-` inside define...endef is left verbatim (defskip).
  r = ir("define blk\nx <- this.y\nendef\n")
  assert "x <- this.y" in r.stdout


def test_compile_capture_triplequote(ir):
  # capture + triple-quote compose: the triple-quote lowers to a `printf` first,
  # then `<-` captures it -> a shell var holding the literal text.
  r = ir("t:\n\tx <- '''foo bar'''\n")
  assert "x=`printf '%s' 'foo bar'`" in r.stdout


def test_compile_capture_singleline_triplequote_has_no_trailing_newline(ir):
  # A single-line triple-quote lowers to `printf '%s'` -- fmt `%s`, no trailing
  # newline (a `\n` only appears in the multi-line `printf '%s\n%s'` form, sourced
  # from REAL source newlines).  So a `printf '%s\n' "$x"` emit with a REQUIRED
  # trailing newline (a line-oriented reader downstream) cannot be replaced by an
  # inline `"""$x"""`; that printf stays hand-written.
  r = ir('t:\n\t"""abc""" | cat\n')
  assert "printf '%s' \"abc\" | cat" in r.stdout
  assert "printf '%s\\n" not in r.stdout


def test_compile_capture_module_needs_bare_leading_lhs(ir):
  # A `<-` lowers to a module capture (`:= $(shell)`) only as the leading statement of a
  # column-0 line.  A bare `X <- cmd` qualifies; a capture that follows other text on the
  # line (a macro-value member here) does not -- it runs in a shell, so it backticks.
  bare = ir("X <- this.y\n")
  assert "X := $(shell ${make} y)" in bare.stdout
  member = ir("NAME = foo; rec <- ${make} x\n")
  assert "rec=`${make} x`" in member.stdout
  assert "rec := $(shell" not in member.stdout


def test_compile_capture_in_inline_recipe_is_shell(ir):
  # A `<-` after a target's `:;` is inside the recipe, so it backticks (not a module
  # capture) -- e.g. `send:; goals <- cmd`.
  r = ir("send:; goals <- this.stdin; export goals\n")
  assert "goals=`${make} stdin`" in r.stdout
  assert "goals :=" not in r.stdout


@pytest.mark.xfail(
  strict=True,
  reason="won't-fix by design. A capture is recognized only at an operator boundary the "
  "scanner can see without understanding shell: line-start or `;`/`&&`/`||`. After a shell "
  "keyword (`then`/`else`/`do`/`{` ...) the arrow sits at a command position that only shell "
  "grammar can identify -- those are context-sensitive reserved words (`echo then` is a plain "
  "argument), not operators -- so recognizing it would mean the capture stage grows a bash "
  "parser. Deliberately unsupported; inside an inline if/then/else, write a plain backtick. "
  "If this ever xpasses, the stage has started parsing shell -- reconsider before dropping "
  "the marker.",
)
def test_compile_capture_after_shell_keyword_needs_shell_parser(ir):
  # aspirational, unsupported: a `<-` inside an inline `if ...; then rec <- ..; fi` would heal
  # to a backtick capture.  Today the arrow after `then` is not at an operator boundary, so it
  # is left verbatim (`then rec <- ..`), which is correct under the no-bash-parser contract.
  r = ir("t:\n\tif x; then rec <- ${make} y; fi\n")
  assert "then rec=`${make} y`" in r.stdout


# --- capture stage: the edge cases the `<-` arrow must NOT touch --------------
# The old naive matcher rewrote ` <- ` ANYWHERE; the anchored stage (bare ident at
# a statement boundary + adjacent arrow) leaves strings, arithmetic, redirects,
# heredocs and `$<` alone.  Tested against the stage directly (no callform).


def test_stage_capture_echo_string_not_corrupted(cmk):
  # THE regression: a literal ` <- ` inside a quoted recipe string is NOT a capture
  # (the ident is not at a statement boundary).  The old matcher corrupted
  # `echo "a <- b"` -> `echo "a=`b"``; the anchored stage leaves it verbatim.
  r = cmk("lang.comp.pipeline.capture", stdin='t:\n\techo "arrow a <- b here"\n')
  assert r.ok, r.stderr
  assert 'echo "arrow a <- b here"' in r.stdout


def test_stage_capture_bash_arithmetic_untouched(cmk):
  # `$((a<-b))` contains `<-` but is inside `$((`, not at a statement boundary.
  r = cmk("lang.comp.pipeline.capture", stdin="t:\n\techo $((a<-b))\n")
  assert r.ok, r.stderr
  assert "$((a<-b))" in r.stdout


def test_stage_capture_arithmetic_in_rhs_preserved(cmk):
  # A capture whose RHS embeds bash arithmetic (with its own `<-`) or a `bc`
  # pipeline: the RHS is captured WHOLESALE, its inner `<-` is not re-parsed.
  arith = cmk(
    "lang.comp.pipeline.capture",
    stdin="t:\n\tx <- bash -c 'echo $((5<-3))'\n",
  )
  assert arith.ok and "x=`bash -c 'echo $((5<-3))'`" in arith.stdout
  bc = cmk("lang.comp.pipeline.capture", stdin="t:\n\tr <- echo '3<-2' | bc\n")
  assert bc.ok and "r=`echo '3<-2' | bc`" in bc.stdout


def test_stage_capture_redirect_from_dash_preserved(cmk):
  # `x < -y` (a space INSIDE the arrow) is a shell redirect, not a capture.
  r = cmk("lang.comp.pipeline.capture", stdin="t:\n\tcat x < -y\n")
  assert r.ok, r.stderr
  assert "cat x < -y" in r.stdout


def test_stage_capture_heredoc_untouched(cmk):
  # `<<-` (tab-stripping heredoc) is not a capture (`<` precedes the `-`).
  r = cmk("lang.comp.pipeline.capture", stdin="t:\n\tcat <<-EOF\n")
  assert r.ok, r.stderr
  assert "cat <<-EOF" in r.stdout


def test_stage_capture_autovar_untouched(cmk):
  # `$<` (first-prereq auto-var) followed by `-` is not a capture (`$` precedes).
  r = cmk("lang.comp.pipeline.capture", stdin="t:\n\tcp $<-bak dest\n")
  assert r.ok, r.stderr
  assert "$<-bak" in r.stdout


# --- triple-quote literals ('''…''' / """…""") ------------------------------
# Lower to a literal, %-safe `printf '%s' '…'` (multi-line: '%s\n%s…').
# NB: a BARE column-0 triple-quote is the module-docstring form, and a bare FIRST recipe
# line is the target-docstring form (both -> the `moduledoc` stage, see its tests below).
# So the bare-lowering cases target the `triplequote` stage directly (immune to the earlier
# docstring stages); the pipe form (content after the close) reaches triplequote via
# `mk.compile` unchanged.


def test_compile_triplequote_basic_pipe(ir):
  r = ir("'''foo bar''' | this.t\n")
  assert "printf '%s' 'foo bar' | ${make} t" in r.stdout


def test_compile_triplequote_internal_double_quote(cmk):
  r = cmk("lang.comp.pipeline.triplequote", stdin="'''say \"hi\"'''\n")
  assert r.ok, r.stderr
  assert "printf '%s' 'say \"hi\"'" in r.stdout


def test_compile_triplequote_double_is_interpolating(cmk):
  # `"""…"""` is the interpolating (DOUBLE-quoted) form: shell `$VAR`/`` `cmd` `` expand.
  r = cmk("lang.comp.pipeline.triplequote", stdin='"""$X"""\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"$X\"" in r.stdout


def test_compile_triplequote_double_internal_single_quote(cmk):
  # A literal single quote sits fine inside the double-quoted form (no escaping).
  r = cmk("lang.comp.pipeline.triplequote", stdin='"""it\'s"""\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"it's\"" in r.stdout


def test_compile_triplequote_percent_is_literal(cmk):
  # `%` is an ARG to `%s`, so it stays literal (a win over raw `printf 'TEXT'`).
  r = cmk("lang.comp.pipeline.triplequote", stdin="'''100%done'''\n")
  assert r.ok, r.stderr
  assert "printf '%s' '100%done'" in r.stdout


def test_compile_triplequote_multiline(ir):
  # spans lines -> one printf with '%s\n%s' and per-line args.
  r = ir("x:\n\t'''L1\nL2''' | this.t\n")
  assert "printf '%s\\n%s' 'L1' 'L2' | ${make} t" in r.stdout


def test_compile_triplequote_multiline_after_preceding_content(ir):
  # a two-line triple-quote (used to add a trailing newline) lowers to a '%s\n%s'
  # printf and keeps the trailing pipe even mid-statement -- so a `printf '%s\n' "$var"`
  # that must follow same-shell statements can be written as `"""$var<newline>"""`.
  # (Regression: moduledoc used to consume the closing line as a stray docstring opener,
  # collapsing this to `printf '%s' "x"` and dropping `| cat`.)
  r = ir('t:\n\techo pre; """x\n""" | cat\n')
  assert "echo pre; printf '%s\\n%s' \"x\" \"\" | cat" in r.stdout


def test_compile_triplequote_multiline_in_class_body(ir):
  # inside a cooked class body a recipe lowers like its top-level twin -- `printf '%s\n%s' "hi"
  # ""` -- for a two-line triple-quote used to add a trailing newline.  (Regression: the frame
  # dedent left the close line's residual indent between the newline and the delimiter, which the
  # lowering kept as content -- `"hi" "  "`.  A whitespace-only final segment is now normalised to
  # empty, the recipe-literal analog of the docstring framing-trim.)
  r = ir('from cmk import class\nclass Foo[|\n  ${self}.m:\n    """hi\n    """ | cat\n|]\n')
  assert "printf '%s\\n%s' \"hi\" \"\" | cat" in r.stdout


def test_compile_triplequote_skips_define_block(ir):
  # python-style '''docstrings''' inside define...endef pass through verbatim.
  r = ir("define blk\nx = '''doc'''\nendef\n")
  assert "x = '''doc'''" in r.stdout


# --- module docstrings (bare column-0 '''…''' -> define __doc__) -------------
# A bare, column-0 triple-quote is the module `__doc__`: newline-preserving
# `define __doc__ … endef` (not a col-0 printf), plus a canonical
# `${__name__}.__doc__` copy that no-ops until __name__ is tracked.


@pytest.mark.docstring
def test_moduledoc_bare_multiline_defines_doc(ir):
  r = ir("'''\nline one\nline two\n'''\n")
  assert "define __doc__\nline one\nline two\nendef" in r.stdout


@pytest.mark.docstring
def test_moduledoc_bare_singleline_defines_doc(ir):
  r = ir("'''one liner'''\n")
  assert "define __doc__\none liner\nendef" in r.stdout


@pytest.mark.docstring
def test_moduledoc_cooked_banana_member_docstring(ir):
  # a `'''docstring'''` as the first (indented) body line of a COOKED `[| .. |]` banana lifts to
  # a sibling `<name>.__doc__` (here `Foo.__doc__`), NOT a recipe `printf` -- so cooked
  # class/machine decls (incl. those indented in an encapsulation `*[| .. |]` block) carry docstrings.
  r = ir("cmk.class Foo[|\n  '''\n  cooked doc line\n  '''\n  ${self}.x := 1\n|]\n")
  assert "$(eval define Foo.__doc__" in r.stdout and "cooked doc line" in r.stdout
  assert "printf '%s" not in r.stdout   # not the recipe string-literal lowering


@pytest.mark.docstring
def test_moduledoc_literal_escapes_dollar(ir):
  # literal ''' keeps `$` verbatim -> escaped to `$$` so make does not expand it.
  r = ir("'''cost $5'''\n")
  assert "define __doc__\ncost $$5\nendef" in r.stdout


@pytest.mark.docstring
def test_moduledoc_double_interpolates_dollar(ir):
  # interpolating """ leaves `$` live (expands on use).
  r = ir('"""cost $5"""\n')
  assert "define __doc__\ncost $5\nendef" in r.stdout


@pytest.mark.docstring
def test_moduledoc_emits_canonical_name_copy(ir):
  # the anticipated (no-op'd) canonical `${__name__}.__doc__` companion.
  r = ir("'''doc'''\n")
  assert "$(if ${__name__},$(eval define ${__name__}.__doc__" in r.stdout


@pytest.mark.docstring
def test_moduledoc_pipe_form_not_captured(ir):
  # a delimiter with trailing content is a pipe form -> triplequote, not __doc__.
  r = ir("'''piped''' | this.t\n")
  assert "define __doc__" not in r.stdout
  assert "printf '%s' 'piped' | ${make} t" in r.stdout


@pytest.mark.docstring
def test_moduledoc_skips_define_block(ir):
  # a bare-looking docstring inside define…endef is not a module docstring.
  r = ir("define blk\n'''inner'''\nendef\n")
  assert "'''inner'''" in r.stdout
  assert "define __doc__" not in r.stdout


@pytest.mark.docstring
def test_moduledoc_second_docstring_warns_and_drops(ir):
  # only the first bare docstring binds __doc__; later ones warn + optimize out.
  r = ir("'''first'''\n\n'''second'''\n")
  assert r.stdout.count("define __doc__") == 1
  assert "first" in r.stdout and "second" not in r.stdout
  assert "moduledoc" in r.stderr


@pytest.mark.docstring
def test_moduledoc_lint_off_silences_warning(ir):
  r = ir("'''a'''\n\n'''b'''\n", env={"CMK_MODULEDOC_LINT": "0"})
  assert "moduledoc" not in r.stderr


@pytest.mark.docstring
def test_moduledoc_member_in_banana_scopes_to_name(ir):
  # a col-0 docstring inside a banana body lifts to a sibling `<name>.__doc__` keyed on the
  # banana's lexical name (here `foo.__doc__`), not the module __doc__.
  r = ir("foo(|\n'''member doc'''\n|)\n")
  assert "$(eval define foo.__doc__${nl}member doc${nl}endef)" in r.stdout
  assert "define __doc__" not in r.stdout


@pytest.mark.docstring
def test_moduledoc_member_coexists_with_module(ir):
  # a module docstring AND a banana-member docstring both survive: member is not seen-gated,
  # nor does it consume the first-wins module slot.
  r = ir("'''the module'''\n\nfoo(|\n'''the member'''\n|)\n")
  assert "define __doc__\nthe module\nendef" in r.stdout
  assert "$(eval define foo.__doc__${nl}the member${nl}endef)" in r.stdout
  assert "moduledoc" not in r.stderr


@pytest.mark.docstring
def test_moduledoc_member_multiline_joins_with_nl(ir):
  r = ir("foo(|\n'''\nline one\nline two\n'''\n|)\n")
  assert "$(eval define foo.__doc__${nl}line one${nl}line two${nl}endef)" in r.stdout


# --- target docstrings (a '''…''' first recipe line, and ${__target__.__doc__}) ---
# A bare triple-quote as the FIRST line of a target's recipe lowers to the canonical
# `@#` recipe-comment form (surfaced by mk.parse/help exactly like a hand-authored @#).
# `${__target__.__doc__}` reflects it at runtime via the same extractor.


def test_targetdoc_first_recipe_line_to_hash(ir):
  r = ir("foo:\n  '''builds the widget'''\n  @true\n")
  assert "\t@# builds the widget" in r.stdout
  assert "printf" not in r.stdout  # not lowered to a triplequote printf


def test_targetdoc_multiline_to_hash(ir):
  r = ir("foo:\n  '''\n  line one\n  line two\n  '''\n  @true\n")
  assert "\t@# line one" in r.stdout and "\t@# line two" in r.stdout
  assert "\t@# \n" not in r.stdout  # no spurious empty @# from the indented close delim


def test_targetdoc_second_recipe_line_stays_printf(ir):
  # only the FIRST recipe line is the docstring; a later ''' is a normal printf.
  r = ir("foo:\n  @echo first\n  '''second'''\n")
  assert "printf '%s' 'second'" in r.stdout
  assert "@# second" not in r.stdout


def test_targetdoc_pipe_form_not_doc(ir):
  # a delimiter with trailing content stays a pipe/printf, never a @# docstring.
  r = ir("foo:\n  '''piped''' | this.t\n")
  assert "@#" not in r.stdout
  assert "printf '%s' 'piped' | ${make} t" in r.stdout


@pytest.mark.docstring
@pytest.mark.xfail(
  strict=True,
  reason="TODO: a decorator relocates above the target to become the first recipe line, "
  "displacing the docstring to the second line, where joinbody lowers it to a printf "
  "(leaks to stdout at runtime) instead of the canonical @# doc comment.  Surfaced by "
  "demos/cmk/kwarg-parsing.cmk, whose decorated `consume` had to drop its docstring for "
  "a plain # comment.  If this xpasses, the docstring lift learned to look past a leading "
  "decorator -- keep the fix and drop this marker.",
)
def test_targetdoc_under_decorator_still_hashes(ir):
  # the docstring is the target's first authored body line even when a decorator precedes it.
  r = ir("@bind.args(from=json, shape)\nfoo:\n  '''builds the widget'''\n  @true\n")
  assert "\t@# builds the widget" in r.stdout
  assert "printf '%s' 'builds the widget'" not in r.stdout


@pytest.mark.docstring
def test_target_doc_accessor_lowers_without_corruption(ir):
  # ${__target__.__doc__} -> ${_cmk.target.doc}; the compound is consumed whole, NOT corrupted
  # into ${${@}.__doc__} by the bare __target__ -> ${@} restore.
  r = ir('foo:\n  echo "${__target__.__doc__}"\n')
  assert "${_cmk.target.doc}" in r.stdout
  assert "${@}.__doc__" not in r.stdout


def test_targetdoc_runtime_reflection(ir, project):
  # end-to-end: a '''-authored target docstring resolves via ${__target__.__doc__}.
  r = _run_cmk(ir, project, "__main__:\n  '''the main doc'''\n  @echo \"doc=[${__target__.__doc__}]\"\n")
  assert r.ok, r.stderr
  assert "doc=[the main doc]" in r.stdout


def test_targetdoc_runtime_dualism_hand_hash(ir, project):
  # a hand-authored @# resolves the same way (one extractor, both authoring forms).
  r = _run_cmk(ir, project, "__main__:\n  @# hand written\n  @echo \"doc=[${__target__.__doc__}]\"\n")
  assert r.ok, r.stderr
  assert "doc=[hand written]" in r.stdout


# --- triple-BACKTICK literals (```…```) -------------------------------------
# Like triple-quote, but DOUBLE-quoted -> standard interpolation (`cmds`, $vars).


def test_compile_triplebacktick_interpolating(ir):
  # the distinguishing behavior: DOUBLE-quoted printf (vs triple-quote's single).
  r = ir("```$X``` | this.t\n")
  assert "printf '%s' \"$X\" | ${make} t" in r.stdout


def test_compile_triplebacktick_backtick_passthrough(cmk):
  # a command-sub inside survives verbatim (interpolated by the shell at runtime).
  r = cmk("lang.comp.pipeline.triplequote", stdin="```a`id`b```\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"a`id`b\"" in r.stdout


def test_compile_triplebacktick_escapes_double_quote(cmk):
  # an internal " is escaped so the double-quoted string stays well-formed.
  r = cmk("lang.comp.pipeline.triplequote", stdin='```say "hi"```\n')
  assert r.ok, r.stderr
  assert 'printf \'%s\' "say \\"hi\\""' in r.stdout


def test_compile_triplebacktick_multiline(ir):
  r = ir("x:\n\t```L1\nL2``` | this.t\n")
  assert 'printf \'%s\\n%s\' "L1" "L2" | ${make} t' in r.stdout


def test_compile_triplebacktick_content_ends_with_backtick(cmk):
  # The closer is the LAST 3 of a backtick run, so the content may end with a
  # backtick (e.g. a command-sub right before the close): ````id```` -> "`id`".
  r = cmk("lang.comp.pipeline.triplequote", stdin="````id````\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"`id`\"" in r.stdout


def test_compile_triplequote_still_literal(ir):
  # regression: the single-quoted (literal) forms are unchanged by the backtick add.
  r = ir("'''$X''' | this.t\n")
  assert "printf '%s' '$X' | ${make} t" in r.stdout


# --- callable targets: this.NAME[stream] / this.NAME'''...''' (.awk.callform) --
# Phase-1 grammar: a target's `[stream]` is its stdin and `(args)` is its `/`-suffix
# arguments (the OLD paren-as-stream form `this.NAME(stream)` was DROPPED -- a target's
# `(...)` is now ALWAYS args).  The `callform` stage runs AFTER dialect (so `this.NAME`
# is already `${make} NAME`) and the tagged `this.NAME'''...'''` form is split into the
# `tagged` stage just ahead of it; neither lowers the literal itself (triplequote does,
# later).  Happy-path tests go through full `mk.compile`; error cases use the standalone
# stage target (`lang.comp.pipeline.callform`, fed the post-dialect `${make} ` form) so the
# nonzero exit is observable -- the full pipe masks a mid-stage failure.


def test_callable_quoted_call(ir):
  r = ir("x:\n\tthis.eval['''(Hi)S''']\n")
  assert "printf '%s' '(Hi)S' | ${make} eval" in r.stdout


def test_callable_quoted_call_doublequote(ir):
  # `"""…"""` is interpolating, so it lowers to a double-quoted printf.
  r = ir('x:\n\tthis.eval["""(Hi)S"""]\n')
  assert "printf '%s' \"(Hi)S\" | ${make} eval" in r.stdout


def test_callable_quoted_call_backtick_interpolates(ir):
  # the ``` delimiter is interpolating: lowers to a DOUBLE-quoted printf.
  r = ir("x:\n\tthis.eval[```$X```]\n")
  assert "printf '%s' \"$X\" | ${make} eval" in r.stdout


def test_callable_tagged(ir):
  r = ir("x:\n\tthis.eval'''(Hi)S'''\n")
  assert "printf '%s' '(Hi)S' | ${make} eval" in r.stdout


def test_callable_tagged_backtick(ir):
  r = ir("x:\n\tthis.eval```$X```\n")
  assert "printf '%s' \"$X\" | ${make} eval" in r.stdout


def test_callable_unquoted_pipes_command(ir):
  # unquoted stream is moved verbatim (its stdout is piped in).
  r = ir("x:\n\tthis.eval[cat f]\n")
  assert "cat f | ${make} eval" in r.stdout


def test_callable_chaining(ir):
  # this.b[this.a] -> ${make} a | ${make} b (inner already lowered by dialect).
  r = ir("x:\n\tthis.b[this.a]\n")
  assert "${make} a | ${make} b" in r.stdout


def test_callable_multiline_quoted(ir):
  r = ir("x:\n\tthis.eval['''L1\nL2''']\n")
  assert "printf '%s\\n%s' 'L1' 'L2' | ${make} eval" in r.stdout


def test_callable_subshell_arg(ir):
  # a subshell stream is spanned by balanced brackets and piped verbatim.
  r = ir("x:\n\tthis.foo[(echo a; echo b)]\n")
  assert "(echo a; echo b) | ${make} foo" in r.stdout


def test_callable_not_a_call_semicolon_subshell(ir):
  # `this.b; (this.a)` is plain shell, NOT a call -- must stay verbatim.
  r = ir("x:\n\tthis.b; (this.a)\n")
  assert "${make} b; (${make} a)" in r.stdout
  assert "${make} a | ${make} b" not in r.stdout


def test_callable_not_a_call_space_before_paren(ir):
  # a space between NAME and `(` means it's not a call.
  r = ir("x:\n\tthis.foo (x)\n")
  assert "${make} foo (x)" in r.stdout


def test_callable_bare_this_unchanged(ir):
  # bare this.foo (no adjacent (/delim) is an ordinary make invocation.
  r = ir("x:\n\tthis.foo bar\n")
  assert "${make} foo bar" in r.stdout


def test_callable_skips_define_block(ir):
  # inert inside define..endef (dialect/callform/triplequote all skip it).
  r = ir("define blk\nthis.t('''x''')\nendef\n")
  assert "this.t('''x''')" in r.stdout


def test_callable_defers_dispatch_form(ir):
  # `.dispatch(target)` is container dispatch (the .awk.dispatch pass), NOT a callable
  # pipe -- callable must leave names ending in `.dispatch` alone.
  r = ir("x:\n\tthis.alice.dispatch(self.task)\n")
  assert "${make} alice.dispatch/self.task" in r.stdout
  assert "self.task | ${make}" not in r.stdout


def test_callable_error_unterminated_unquoted(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin="x:\n\t${make} t[a b\n")
  assert not r.ok
  assert "compose.mk (cmk:callform) error:" in r.stderr
  assert "unterminated" in r.stderr
  assert "at line" in r.stderr


def test_callable_error_unterminated_literal(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin="x:\n\t${make} t['''oops\n")
  assert not r.ok
  assert "unterminated triple-quoted literal" in r.stderr


def test_callable_error_mixed_content(cmk):
  r = cmk("lang.comp.pipeline.callform", stdin="x:\n\t${make} t['''a''' more]\n")
  assert not r.ok
  assert "expected ']'" in r.stderr


# --- recipe-body joining (.awk.joinbody) ------------------------------------
# The newline-separated lines of a recipe body are joined into ONE shell with
# ` && \` (shared state, fail-fast).


def test_compile_joinbody_basic(ir):
  r = ir("x:\n\tcmd1\n\tcmd2\n")
  assert "cmd1 && \\\n" in r.stdout
  assert "\tcmd2" in r.stdout


# --- recipe_join compiler pragma (cmk_pragma) -------------------------------
# `# cmk_pragma ::: { "recipe_join": ... } :::` overrides the forced ` && `
# recipe-join connector: `&&` (default), `;` (run-all), or `none` (no join).


def test_pragma_recipe_join_default_is_and(ir):
  # No pragma -> the default ` && \` connector (regression guard).
  r = ir("x:\n\tcmd1\n\tcmd2\n")
  assert "cmd1 && \\\n" in r.stdout


def test_pragma_recipe_join_semicolon(ir):
  src = '# cmk_pragma ::: { "recipe_join": ";" } :::\nx:\n\tcmd1\n\tcmd2\n'
  r = ir(src)
  assert "cmd1 ; \\\n" in r.stdout
  assert "cmd1 && \\" not in r.stdout


def test_pragma_recipe_join_none(ir):
  # `none` emits each line as its own recipe-line: no connector, no continuation.
  src = '# cmk_pragma ::: { "recipe_join": "none" } :::\nx:\n\tcmd1\n\tcmd2\n'
  r = ir(src)
  assert "\tcmd1\n\tcmd2" in r.stdout
  assert "cmd1 && \\" not in r.stdout
  assert "cmd1 ; \\" not in r.stdout


@pytest.mark.parametrize("marker", ["cmk_pragma", "CMK_PRAGMA", "Cmk_Pragma"])
def test_pragma_marker_case_insensitive(ir, marker):
  # The `cmk_pragma :::` MARKER is matched case-insensitively (CMK_PRAGMA / Cmk_Pragma /
  # ... all work); using recipe_join=`;` as the observable proves the pragma was detected.
  # The JSON keys/values keep their original case (recipe_join stays lowercase here).
  src = f'# {marker} ::: {{ "recipe_join": ";" }} :::\nx:\n\tcmd1\n\tcmd2\n'
  r = ir(src)
  assert "cmd1 ; \\\n" in r.stdout  # pragma took effect -> marker detected
  assert "cmd1 && \\" not in r.stdout


def test_pragma_coexists_with_dialect(ir):
  # A pragma hint and a dialect hint in the same header both apply (the dialect
  # parser is marker-aware, so the pragma's JSON is not mistaken for a dialect).
  src = (
    '# cmk_dialect ::: [ ["this.","${make} "] ] :::\n'
    '# cmk_pragma ::: { "recipe_join": ";" } :::\n'
    "x:\n\tthis.y\n\tcmd2\n"
  )
  r = ir(src)
  assert "${make} y ; \\\n" in r.stdout  # dialect + pragma both applied


def test_compile_joinbody_keeps_trailing_connector(ir):
  # a line already ending in a connector just continues (no extra `&&`).
  r = ir("x:\n\tcmd1 ;\n\tcmd2\n")
  assert "cmd1 ; \\\n" in r.stdout
  assert "cmd1 ; && " not in r.stdout


def test_compile_joinbody_prefix_stands_alone(ir):
  # `-`/`+`-prefixed lines are not joined (make honors the prefix only at a
  # recipe-line start).
  r = ir("x:\n\tcmd1\n\t-cmd2\n\tcmd3\n")
  assert "-cmd2" in r.stdout
  assert "cmd1 && \\" not in r.stdout  # cmd1 flushed before the -line
  assert "-cmd2 && \\" not in r.stdout  # -line not joined into cmd3


def test_compile_joinbody_single_line_unchanged(ir):
  r = ir("x:\n\tonly\n")
  assert "\tonly" in r.stdout
  assert "only && \\" not in r.stdout


def test_compile_joinbody_explicit_continuation(ir):
  # minify zips the `\`-continued `a`+`b` into one command; joinbody adds ` && `
  # only before the separate `c` -- never between `a` and `b`.
  r = ir("x:\n\ta \\\n\tb\n\tc\n")
  assert "a b && \\\n" in r.stdout
  assert "\tc" in r.stdout


def test_compile_joinbody_skips_define_block(ir):
  # define...endef bodies (polyglot/awk) are not joined.
  r = ir("define blk\nl1\nl2\nendef\n")
  assert "l1\nl2" in r.stdout
  assert "l1 && \\" not in r.stdout


def test_joinbody_skips_nested_define_block(cmk):
  # `.awk.joinbody` depth-tracks: an inner endef must not re-enable joining for the
  # rest of the OUTER body (the tab-led lines stay raw, not ` && \`-chained).
  r = cmk(
    "io.awk/.awk.joinbody",
    stdin="define outer\ndefine inner\ni\nendef\n\tline1\n\tline2\nendef\n",
  )
  assert r.ok, r.stderr
  assert "line1 && \\" not in r.stdout  # inside outer define: not joined
  assert "\tline1\n\tline2" in r.stdout


def test_compile_joinbody_strips_inline_comment(ir):
  # a trailing `# comment` on a recipe line is stripped BEFORE the ` && ` join, so it
  # cannot swallow the rest of the joined body.
  r = ir("x:\n\techo one  # a comment\n\techo two\n")
  assert "echo one && \\" in r.stdout
  assert "echo two" in r.stdout
  assert "# a comment" not in r.stdout


def test_compile_joinbody_inline_comment_drops_full_comment_line(cmk):
  # a recipe line that is ONLY a comment vanishes (does not become an empty `&&` arm).
  r = cmk(
    "mk.compile", stdin="x:\n\techo one\n\t# just a comment\n\techo two\n"
  )
  assert r.ok, r.stderr
  assert "echo one && \\" in r.stdout
  assert "echo two" in r.stdout
  assert "just a comment" not in r.stdout


@pytest.mark.docstring
def test_compile_joinbody_preserves_leading_docstring(ir):
  # A target's leading `@#` block is its docstring: kept verbatim as separate
  # `\t@#` lines (never folded into the ` && ` body) so help/mk.parse can read it.
  r = ir("x:\n\t@# doc one\n\t@# doc two\n\techo hi\n")
  assert "\t@# doc one\n" in r.stdout
  assert "\t@# doc two\n" in r.stdout
  assert "echo hi" in r.stdout
  assert "doc one && \\" not in r.stdout  # docstring not joined into the body


@pytest.mark.docstring
def test_compile_joinbody_strips_midrecipe_docstring(ir):
  # A `@#` AFTER the body has started is a throwaway annotation: dropped, never
  # folded into the joined recipe.
  r = ir("x:\n\techo hi\n\t@# mid note\n\techo bye\n")
  assert "mid note" not in r.stdout
  assert "echo hi && \\" in r.stdout
  assert "echo bye" in r.stdout


def test_compile_joinbody_preserves_quoted_and_shell_hash(ir):
  # `#` inside quotes / `$(...)` / a shell `${V#x}` is NOT a comment and must survive.
  r = ir(
    'x:\n\techo "a # b"  # strip\n\tv=abc; echo $${v#a}  # strip\n\techo end\n',
  )
  assert 'echo "a # b" && \\' in r.stdout
  assert "echo $${v#a} && \\" in r.stdout
  assert "# strip" not in r.stdout


# --- python-style indentation: space OR tab recipe bodies (lang.comp.pipeline.indent) --
# The `indent` stage runs LAST in the preprocess chain (after sugar lowered its
# literal blocks to define..endef), normalizing a consistently SPACE-indented body
# to the leading tab Make needs, passing TAB bodies through verbatim, and erroring
# on mixed (tabs+spaces in one indent) or mismatched indentation. Error cases use
# the standalone stage target (`lang.comp.pipeline.indent`) so the nonzero exit is
# observable -- the full `mk.compile` pipe masks a mid-pipe failure (same as the
# decorator-stage errors above); the real `mk.interpret!` path does surface it.


def test_compile_space_indented_recipe(ir):
  # A space-indented recipe body compiles: spaces -> one leading tab, then joined.
  r = ir("x:\n    cmd1\n    cmd2\n")
  assert (
    "cmd1 && \\\n" in r.stdout
  )  # joinbody saw it as a recipe (i.e. tab-led)
  assert "\tcmd2" in r.stdout  # normalized to a tab, not left as spaces
  assert "    cmd2" not in r.stdout  # the original spaces are gone


def test_indent_stage_normalizes_spaces_to_tab(cmk):
  # The stage itself rewrites leading spaces to a single tab.
  r = cmk("lang.comp.pipeline.indent", stdin="x:\n    a\n    b\n")
  assert r.ok, r.stderr
  assert "\ta\n" in r.stdout and "\tb\n" in r.stdout
  assert "    a" not in r.stdout


def test_indent_stage_tab_body_unchanged(cmk):
  # Back-compat: tab-indented bodies pass through verbatim (incl. deeper tabs).
  r = cmk("lang.comp.pipeline.indent", stdin="x:\n\ta\n\t\tb\n")
  assert r.ok, r.stderr
  assert "\ta\n" in r.stdout and "\t\tb\n" in r.stdout


def test_indent_stage_skips_define_block(cmk):
  # define..endef data (e.g. lowered sugar blocks: compose YAML) is verbatim.
  r = cmk("lang.comp.pipeline.indent", stdin="define blk\n    raw spaces\nendef\n")
  assert r.ok, r.stderr
  assert "    raw spaces" in r.stdout  # NOT rewritten to a tab


def test_indent_stage_skips_nested_define_block(cmk):
  # Depth-tracked: a NESTED define's inner endef must not re-enable indent
  # rewriting for the rest of the OUTER body (space-indent stays raw).
  r = cmk(
    "lang.comp.pipeline.indent",
    stdin="define outer\ndefine inner\ni\nendef\n    raw spaces\nendef\n",
  )
  assert r.ok, r.stderr
  assert "    raw spaces" in r.stdout  # still inside outer define: verbatim


def test_indent_mixed_tabs_and_spaces_errors(cmk):
  # A single indent that mixes a tab and spaces is rejected ("mixed mode").
  r = cmk("lang.comp.pipeline.indent", stdin="x:\n\t  cmd\n")
  assert not r.ok
  assert "mixes tabs and spaces" in r.stderr


def test_indent_mismatched_spaces_errors(cmk):
  # Inconsistent space-indent within one body is rejected ("mismatched").
  r = cmk("lang.comp.pipeline.indent", stdin="x:\n    cmd1\n  cmd2\n")
  assert not r.ok
  assert "inconsistent indentation" in r.stderr


# --- generic CMK_PRAGMA_* namespace (pragma -> compiled-output env injection) ---
# A pragma key `foo` is normalized (upcase, ./- -> _) and injected as `export CMK_PRAGMA_FOO := ..`
# at the top of the compiled output; consumers read it back via the __pragma__.get/__pragma__.append
# resolvers (pragma > env > default).  The compiler ONLY ever writes the CMK_PRAGMA_ namespace.

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def test_pragma_injects_namespaced_var_and_joins(ir):
  src = '# cmk_pragma ::: { "recipe_join": ";", "custom_flag": "1" } :::\nx:\n\tc1\n\tc2\n'
  r = ir(src)
  assert "export CMK_PRAGMA_RECIPE_JOIN := ;" in r.stdout
  assert "export CMK_PRAGMA_CUSTOM_FLAG := 1" in r.stdout
  assert "c1 ; \\\n" in r.stdout  # recipe_join still drives the joinbody


def test_pragma_key_normalization(ir):
  # dotted / hyphen / mixed-case keys all fold to the same CMK_PRAGMA_ var.
  for key in ("recipe.join", "recipe-join", "RECIPE_JOIN"):
    src = '# cmk_pragma ::: { "%s": ";" } :::\nx:; @true\n' % key
    r = ir(src)
    assert "export CMK_PRAGMA_RECIPE_JOIN := ;" in r.stdout, key


def test_pragma_uppercase_key_warns(ir):
  src = '# cmk_pragma ::: { "VM_LEGACY": "1" } :::\nx:; @true\n'
  r = ir(src, env={"CMK_COMPILER_VERBOSE": "1"})
  assert "prefer lowercase" in r.stderr
  assert "export CMK_PRAGMA_VM_LEGACY := 1" in r.stdout  # still normalizes


def test_pragma_array_value_space_joined(ir):
  src = '# cmk_pragma ::: { "cmk_post": ["a.x","b.y"] } :::\nx:; @true\n'
  r = ir(src)
  assert "export CMK_PRAGMA_CMK_POST := a.x b.y" in r.stdout


def test_pragma_cmk_pre_emits_namespaced_var(ir):
  # `cmk_pre` (the pre-pipeline boot stage, symmetric with cmk_post) injects
  # CMK_PRAGMA_CMK_PRE, consumed by mk.super.boot before the main pipeline.
  src = '# cmk_pragma ::: { "cmk_pre": ["a.x","b.y"] } :::\nx:; @true\n'
  r = ir(src)
  assert "export CMK_PRAGMA_CMK_PRE := a.x b.y" in r.stdout


def test_pragma_cannot_clobber_internal_vars(ir):
  # A key named after an internal var lands in CMK_PRAGMA_, NEVER the bare CMK_ var.
  src = '# cmk_pragma ::: { "internal": "1", "host": "0" } :::\nx:; @true\n'
  r = ir(src)
  assert "export CMK_PRAGMA_INTERNAL := 1" in r.stdout
  assert "export CMK_PRAGMA_HOST := 0" in r.stdout
  assert "export CMK_INTERNAL :=" not in r.stdout
  assert "export CMK_HOST :=" not in r.stdout


def test_pragma_no_pragma_no_injection(ir):
  # A file with no pragma header injects nothing and keeps the default && join.
  r = ir("x:\n\tc1\n\tc2\n")
  assert "CMK_PRAGMA_" not in r.stdout
  assert "c1 && \\\n" in r.stdout


# --- pragma JSON5 tolerance + loud-failure (regression) ----------------------
# Two issues a strict-jq pragma parser had: (1) a typo'd/invalid JSON body was
# dropped SILENTLY -- the pragma just never applied, with no diagnostic; and
# (2) it parsed in strict mode, rejecting the trailing commas + `//` comments a
# hand-written header naturally grows.  The parser now normalizes JSON5 first
# (trailing commas, `//` line-comments) and ABORTS loudly on genuinely-bad JSON.


def test_pragma_trailing_comma_tolerated(ir):
  # A trailing comma before `}` no longer trips strict-mode -- the pragma applies.
  src = '# cmk_pragma ::: { "recipe_join": ";", } :::\nx:\n\tcmd1\n\tcmd2\n'
  r = ir(src)
  assert "cmd1 ; \\\n" in r.stdout  # pragma parsed -> connector applied


def test_pragma_trailing_comma_in_array_tolerated(ir):
  # ... including a trailing comma inside an array value.
  src = '# cmk_pragma ::: { "cmk_post": ["a.x","b.y",] } :::\nx:; @true\n'
  r = ir(src)
  assert "export CMK_PRAGMA_CMK_POST := a.x b.y" in r.stdout


def test_pragma_json5_line_comments_tolerated(ir):
  # `//` line-comments (JSON5-style) inside a multi-line pragma body are stripped.
  src = (
    "# cmk_pragma ::: {\n"
    "#   // pick the run-all connector\n"
    '#   "recipe_join": ";"\n'
    "# } :::\n"
    "x:\n\tcmd1\n\tcmd2\n"
  )
  r = ir(src)
  assert "cmd1 ; \\\n" in r.stdout


def test_pragma_url_value_survives_comment_strip(ir):
  # The `//` comment-strip is guarded: a `://` inside a string value (e.g. a URL)
  # is NOT mistaken for a comment.
  src = '# cmk_pragma ::: { "site": "http://example.com/x" } :::\nx:; @true\n'
  r = ir(src)
  assert "export CMK_PRAGMA_SITE := http://example.com/x" in r.stdout


def test_pragma_invalid_json_fails_loudly(ir):
  # A genuinely-malformed body (missing `:`) must NOT be silently ignored: the
  # compile aborts non-zero and names the failure (no silent pragma drop).
  src = '# cmk_pragma ::: { "recipe_join" ";" } :::\nx:\n\tcmd1\n'
  r = ir(src, ok=False)  # failure-path: keep the raw non-zero result
  assert not r.ok, (
    "invalid pragma JSON must fail the compile, not pass silently"
  )
  assert "failed parsing pragma" in r.stderr


def _probe(tmp_path):
  mk = tmp_path / "probe.mk"
  mk.write_text(
    "include %s\n"
    "probe:; @printf 'S=[%%s] L=[%%s]\\n' '$(call __pragma__.get, foo, def)' '$(call __pragma__.append, bar, def)'\n"
    % COMPOSE_MK
  )
  return mk


def test_resolver_scalar_precedence_and_warning(cmk, tmp_path):
  mk = _probe(tmp_path)
  # default
  r = cmk("probe", makefile=mk)
  assert "S=[def]" in r.stdout, r.stdout
  # env only
  r = cmk("probe", makefile=mk, env={"CMK_FOO": "envv"})
  assert "S=[envv]" in r.stdout
  # pragma wins + supersession warning
  r = cmk(
    "probe", makefile=mk, env={"CMK_FOO": "envv", "CMK_PRAGMA_FOO": "pragv"}
  )
  assert "S=[pragv]" in r.stdout
  assert "supersedes env CMK_FOO=envv" in r.stderr
  # pragma only -> no warning (no invoker env)
  r = cmk("probe", makefile=mk, env={"CMK_PRAGMA_FOO": "pragv"})
  assert "S=[pragv]" in r.stdout
  assert "supersedes" not in r.stderr


def test_resolver_list_accumulates(cmk, tmp_path):
  mk = _probe(tmp_path)
  r = cmk("probe", makefile=mk, env={"CMK_BAR": "a", "CMK_PRAGMA_BAR": "b"})
  assert "L=[a b]" in r.stdout, r.stdout  # BOTH contribute (no winner)


def test_resolver_default_when_unset(cmk, tmp_path):
  # Neither pragma nor env set -> the default is returned (both scalar and list).
  mk = _probe(tmp_path)
  r = cmk("probe", makefile=mk)
  assert "S=[def]" in r.stdout and "L=[def]" in r.stdout, r.stdout


def _keyprobe(tmp_path, key):
  # A probe that READS one pragma key back via the resolver, to exercise read-side key handling.
  mk = tmp_path / "kp.mk"
  mk.write_text(
    "include %s\n"
    'probe:; @printf "G=[%%s]\\n" "$(call __pragma__.get, %s, d)"\n'
    % (COMPOSE_MK, key)
  )
  return mk


def test_resolver_normalizes_key_on_read(cmk, tmp_path):
  # The KEY is normalized at READ time too (upcase, ./- -> _): a dotted name reads the same
  # CMK_PRAGMA_ var the compiler would have written for `my_key`.
  mk = _keyprobe(tmp_path, "my.key")
  r = cmk("probe", makefile=mk, env={"CMK_PRAGMA_MY_KEY": "hit"})
  assert "G=[hit]" in r.stdout, r.stdout


def test_resolver_cmk_prefixed_key_reads_bare_var(cmk, tmp_path):
  # A key that upcases to CMK_<X> (a cmk_* knob) names its env var DIRECTLY (the __pragma__.envvar
  # dual-shape logic, read side): `cmk_myflag` reads CMK_MYFLAG, NEVER CMK_CMK_MYFLAG.
  mk = _keyprobe(tmp_path, "cmk_myflag")
  r = cmk("probe", makefile=mk, env={"CMK_MYFLAG": "bare"})
  assert "G=[bare]" in r.stdout, r.stdout
  r = cmk("probe", makefile=mk, env={"CMK_CMK_MYFLAG": "doubled"})
  assert "G=[d]" in r.stdout, (
    r.stdout
  )  # CMK_CMK_MYFLAG is NOT the var -> falls to default


# --- ${__pragma__} snapshot reader (the resolved manifest as one JSON object) ----------------


def test_pragma_snapshot_lowercases_keys_and_preserves_values(cmk):
  # ${__pragma__} (a.k.a `${make} __pragma__`) emits the CMK_PRAGMA_* manifest as JSON: keys are
  # lower-cased (CMK_PRAGMA_RECIPE_JOIN -> recipe_join) and values are kept verbatim, INCLUDING a
  # value that itself contains `=`.
  r = cmk(
    "__pragma__",
    env={"CMK_PRAGMA_RECIPE_JOIN": ";", "CMK_PRAGMA_SITE": "http://x=y&z=1"},
  )
  assert r.ok, r.stderr
  obj = json.loads(r.stdout.strip())  # raises (fails) if not legal JSON
  assert obj.get("recipe_join") == ";", obj
  assert obj.get("site") == "http://x=y&z=1", (
    obj
  )  # `=` inside the value survives
  assert (
    "CMK_PRAGMA_RECIPE_JOIN" not in obj
  )  # the raw env NAME never leaks into the object


def test_pragma_snapshot_values_are_strings(cmk):
  # The manifest is stringified in the env, so the snapshot is faithful-to-storage: a numeric-looking
  # pragma comes back as the STRING "1", not the number 1.
  r = cmk("__pragma__", env={"CMK_PRAGMA_VM_TRACE": "1"})
  assert r.ok, r.stderr
  obj = json.loads(r.stdout.strip())
  assert isinstance(obj, dict) and obj.get("vm_trace") == "1", obj


# --- compiler_pre / compiler_post: extra preprocessor stages spliced around the core chain ----


def _chain(tmp_path, macro="lang.comp.stages.all"):
  # A probe makefile that echoes an effective-stage-chain macro (so we can inspect the splice directly,
  # without needing the injected stages to actually resolve to `.cmk.<name>` transforms).
  mk = tmp_path / "chain.mk"
  mk.write_text("include %s\np:; @echo [$(%s)]\n" % (COMPOSE_MK, macro))
  return mk


def test_compiler_stage_chain_default_is_core_only(cmk, tmp_path):
  # With no pragma/env, the effective chain equals the core `lang.comp.stages` (starts minify, ends
  # capture).  `unsentinel` is NOT a core stage: it runs as a finalization pass after joinbody,
  # so joinbody can join cooked bodies while they are still `⟅`-sentineled.
  out = cmk("p", makefile=_chain(tmp_path)).stdout.strip().strip("[]").split()
  assert out[0] == "minify" and out[-1] == "capture", out


def test_compiler_pre_post_splice_around_core(cmk, tmp_path):
  # `compiler_pre` prepends and `compiler_post` appends to the core chain (distinct names so the splice
  # is unambiguous; the core stages remain in the middle, unreordered).
  r = cmk(
    "p",
    makefile=_chain(tmp_path),
    env={"CMK_PRAGMA_COMPILER_PRE": "aaa", "CMK_PRAGMA_COMPILER_POST": "zzz"},
  )
  out = r.stdout.strip().strip("[]").split()
  assert out[0] == "aaa", out  # pre prepended
  assert out[-1] == "zzz", out  # post appended
  assert (
    "minify" in out and "capture" in out
  )  # core chain preserved between (unsentinel is a post-joinbody finalization pass, not a core stage)


def test_compiler_pre_accumulates_env_and_pragma(cmk, tmp_path):
  # The knob is a LIST read via the ACCUMULATE resolver: the env var AND the pragma BOTH contribute.
  r = cmk(
    "p",
    makefile=_chain(tmp_path, "lang.comp.stages.pre"),
    env={
      "CMK_COMPILER_PRE": "envstage",
      "CMK_PRAGMA_COMPILER_PRE": "pragstage",
    },
  )
  pre = r.stdout.strip().strip("[]").split()
  assert "envstage" in pre and "pragstage" in pre, pre  # +=, not replace


def test_compiler_pre_unknown_stage_is_skipped_not_fatal(ir):
  # A name with no `.cmk.<name>` macro is skipped with a warning -- it does NOT crash the fused pipeline
  # (no empty pipe segment) and the compile still produces valid output.
  src = (
    '# cmk_pragma ::: { "compiler_pre": ["bogusxyz"] } :::\nx:\n\tc1\n\tc2\n'
  )
  r = ir(src)
  assert "bogusxyz" in r.stderr and "skipped" in r.stderr
  assert "c1 && \\\n" in r.stdout  # default join preserved, compile intact


def test_compiler_post_real_stage_compiles(ir):
  # Splicing a REAL core stage after the chain compiles cleanly (here unsentinel, an idempotent no-op
  # for this input) -- proving an injected stage that resolves to a `.cmk.<name>` macro actually runs.
  src = '# cmk_pragma ::: { "compiler_post": ["unsentinel"] } :::\nx:\n\tc1\n\tc2\n'
  r = ir(src)
  assert "c1 && \\\n" in r.stdout


def test_compiler_pre_lifts_plugin_stage(ir):
  # A compiler_pre name with NO core `.cmk.<name>` macro is LIFTED from a plugin's `_cmk_blk_<name>` block
  # on CMK_PLUGINS_DIR and run as a stage (plugins are not loaded at compile, so the block is extracted
  # from the file).  Proven with the VM plugin's `_cmk_blk_vm_hydrate` (ships in .cmk/virtual-machine.cmk):
  # it prepends `@vm.ctx.receive`, which the decorators stage lowers to a `vm.ctx.hydrate` call in the
  # recipe -- visible in the compiled output.  This is the mechanism that replaced the bespoke `_vmhy`.
  src = '# cmk_pragma ::: { "compiler_pre": ["vm_hydrate"] } :::\nmytgt:\n\t@echo hi\n'
  # cmk runs in a tmp cwd, so point the lift at the repo's plugin dir (absolute) to find the block.
  r = ir(
    src,
    env={"CMK_PLUGINS_DIR": str(COMPOSE_MK.parent / ".cmk")},
  )
  assert "vm.ctx.hydrate" in r.stdout, r.stdout


def test_vm_hydrate_bare_pragma_is_inert(ir):
  # A bare `vm_hydrate: true` pragma is NOT a core alias: core hard-codes no VM concept, so it injects
  # nothing on its own.  The stage is requested ONLY via the generic `compiler_pre: ["vm_hydrate"]`
  # (see test_compiler_pre_lifts_plugin_stage).  Regression guard against re-coupling core to vm_hydrate.
  src = '# cmk_pragma ::: { "vm_hydrate": true } :::\nmytgt:\n\t@echo hi\n'
  r = ir(
    src,
    env={"CMK_PLUGINS_DIR": str(COMPOSE_MK.parent / ".cmk")},
  )
  assert "vm.ctx.hydrate" not in r.stdout, r.stdout


# --- lang.transpile: bare includable fragment (shared primitive) -------------
# `lang.transpile` is the transpile chain WITHOUT the stand-alone wrapper: no shebang,
# no `MAKEFILE_LIST+=`, no `mk.src` context embed -- so its output is safe to include.
# It backs native_target/cmk.cook and the hosted-partition cache; `cmk transpile`
# is the front-end verb.


def test_lang_transpile_lowers_callforms(cmk):
  r = cmk("lang.transpile", stdin="foo:\n  cmk.log(hi)\n")
  assert r.ok, r.stderr
  assert "$(call log,hi)" in r.stdout, r.stdout


def test_lang_transpile_emits_bare_fragment(cmk):
  # No stand-alone wrapper -- unlike mk.compile.
  r = cmk("lang.transpile", stdin="foo:\n  cmk.log(hi)\n")
  assert r.ok, r.stderr
  assert "#!/usr/bin/env" not in r.stdout, r.stdout
  assert "MAKEFILE_LIST+=" not in r.stdout, r.stdout
  assert "؆" not in r.stdout, "cmk. sentinel not restored"


def test_lang_transpile_joins_multiline_recipe(cmk):
  # The joinbody stage is load-bearing: a var set on one line must survive to the
  # next (same shell), so transpiled lines are joined with ` && \`.
  src = 'foo:\n  items="a b c"\n  for it in $${items}; do echo $${it}; done\n'
  r = cmk("lang.transpile", stdin=src)
  assert r.ok, r.stderr
  assert "&& \\" in r.stdout, r.stdout


def test_lang_transpile_vs_mk_compile_wrapper(cmk, ir):
  # Negative-diff: mk.compile DOES carry the wrapper that lang.transpile omits.
  stdin = "foo:\n  cmk.log(hi)\n"
  assert "MAKEFILE_LIST+=" in ir(stdin).stdout
  assert "MAKEFILE_LIST+=" not in cmk("lang.transpile", stdin=stdin).stdout


# --- native_target / cmk.cook: JIT-compile a CMK `define` on first call ---
# Exercised from a VANILLA makefile that only `include`s compose.mk (no supervisor).


def _native_env(tmp_path):
  # Isolate the JIT cache per-test.  It otherwise lives in the shared
  # `${CMK_STAGE_DIR}/native` (= ~/.cache), so a sibling test compiling the same
  # `define` warms it and a later `cache MISS` assertion sees a HIT (order-dependent
  # flake).  `CMK_NATIVE_CACHE ?=` honors the env, which also reaches the JIT sub-makes.
  return {"CMK_NATIVE_CACHE": str(tmp_path / "native")}


def _native_wrapper(tmp_path, macro):
  mk = tmp_path / "nat.mk"
  # A multi-line recipe (x=1 then echo) proves the joinbody shared-shell property.
  mk.write_text(
    "include %s\n"
    "define impl\n"
    "impl.entry:\n"
    "  cmk.log(NATIVE-OK)\n"
    "  x=1\n"
    "  echo val=$${x}\n"
    "endef\n"
    "go:; $(call %s, impl, impl.entry)\n" % (COMPOSE_MK, macro)
  )
  return mk


def test_native_target_runs_from_vanilla_make(cmk, tmp_path):
  r = cmk("go", makefile=_native_wrapper(tmp_path, "native_target"), env=_native_env(tmp_path))
  assert r.ok, r.stderr
  both = r.stdout + r.stderr
  assert "NATIVE-OK" in both, both
  assert "val=1" in both, "multi-line recipe must share a shell (joinbody)"


def test_module_cook_runs_from_vanilla_make(cmk, tmp_path):
  r = cmk("go", makefile=_native_wrapper(tmp_path, "cmk.cook"), env=_native_env(tmp_path))
  assert r.ok, r.stderr
  both = r.stdout + r.stderr
  assert "NATIVE-OK" in both, both
  assert "val=1" in both, "multi-line recipe must share a shell (joinbody)"


def test_native_target_miss_then_hit(cmk, tmp_path):
  mk = _native_wrapper(tmp_path, "native_target")
  env = _native_env(tmp_path)  # per-test cache -> first run is a guaranteed cold MISS
  r1 = cmk("go", makefile=mk, env=env)
  assert "cache MISS" in (r1.stdout + r1.stderr), r1.stderr
  r2 = cmk("go", makefile=mk, env=env)
  assert "cache HIT" in (r2.stdout + r2.stderr), r2.stderr


def test_module_cook_two_targets(cmk, tmp_path):
  mk = tmp_path / "nat2.mk"
  mk.write_text(
    "include %s\n"
    "define svc\n"
    "svc.up:; cmk.log(UP)\n"
    "svc.down:; cmk.log(DOWN)\n"
    "endef\n"
    "go:; $(call cmk.cook, svc, svc.up)\n" % COMPOSE_MK
  )
  r = cmk("go", makefile=mk, env=_native_env(tmp_path))
  assert r.ok, r.stderr
  assert "UP" in (r.stdout + r.stderr)


def test_native_strip_arg_edge(cmk, tmp_path):
  # A `$(call m, name )` arg carries surrounding space; $(value $(strip ..)) must cope.
  mk = tmp_path / "natsp.mk"
  mk.write_text(
    "include %s\n"
    "define impl\n"
    "impl.entry:; cmk.log(STRIP-OK)\n"
    "endef\n"
    "go:; $(call native_target, impl , impl.entry )\n" % COMPOSE_MK
  )
  r = cmk("go", makefile=mk, env=_native_env(tmp_path))
  assert r.ok, r.stderr
  assert "STRIP-OK" in (r.stdout + r.stderr)


# --- fluent chain junction: per-receiver operator override -----------------------------
# A fluent chain `a().b().c()` lowers each `).<recv>(` junction to a ` | ` shell pipe by
# default.  A `<name>.__junction__ := <op>` declaration (pre-scanned into -v JUNCTIONS)
# overrides the boundary landing on `<name>`, letting a KIND compose by sequencing /
# concatenation instead of a pipe -- the seam bash_clause builds on.  See scratch/dsl-bash.cmk (retired junction sketch).


def test_junction_override_operator(ir):
  # `then.__junction__ := ;` makes the a->then junction a ` ; ` sequence, not a pipe.
  src = "blockref a(||)\nblockref then(||)\nthen.__junction__ := ;\n__main__:\n\ta().then(x)\n"
  r = ir(src)
  assert ") ; $(if" in r.stdout        # boundary landing on `then` is the declared op
  assert ") | $(if" not in r.stdout    # no default pipe boundary leaked


def test_junction_default_pipes(ir):
  # Regression: with no `.__junction__` declaration every chain junction stays a ` | ` pipe.
  src = "blockref a(||)\nblockref b(||)\n__main__:\n\ta().b(x)\n"
  r = ir(src)
  assert ") | $(if" in r.stdout        # default pipe boundary
  assert ") ; $(if" not in r.stdout


def test_junction_override_is_per_receiver(ir):
  # The override keys on the receiver the junction LANDS on: in `a().then(x).b(y)` with only
  # `then` overridden, a->then is ` ; ` while then->b stays a ` | ` pipe.
  src = (
    "blockref a(||)\nblockref then(||)\nblockref b(||)\n"
    "then.__junction__ := ;\n__main__:\n\ta().then(x).b(y)\n"
  )
  r = ir(src)
  assert ") ; $(if" in r.stdout        # a -> then (overridden)
  assert ") | $(if" in r.stdout        # then -> b (default pipe)


# --- banana-dot-banana: `.` as an overridable operator over banana constructions -------
# `foo(| a |).bar(| b |)` (both sides bananas) lifts each operand to a hoisted construction
# and folds them left-assoc via the `.__dot__` dunder, then invokes the result's
# `.__call__`.  A `.name(<args>)` right side (parens, not `(|`) stays the anonymous-immediate
# METHOD call instead.  See demos/cmk/banana-fluent.cmk.


def test_banana_dot_lifts_and_folds(ir):
  src = "blockref foo(||)\nblockref bar(||)\n__main__:\n\tfoo(| a |).bar(| b |)\n"
  r = ir(src)
  assert "lang.grammar.dot.new,foo,__foo." in r.stdout  # left operand constructed, named for its ctor (guarded)
  assert "lang.grammar.dot.new,bar,__bar." in r.stdout  # right operand constructed, named for its ctor (guarded)
  assert "lang.grammar.dot.op," in r.stdout             # folded via the dot dunder (guarded)
  assert "lang.grammar.dot.run," in r.stdout            # result invoked inline (guarded)


def test_banana_dot_three_operands_two_folds(ir):
  src = "blockref k(||)\n__main__:\n\tk(| a |).k(| b |).k(| c |)\n"
  r = ir(src)
  assert r.stdout.count("lang.grammar.dot.op,") == 2    # n-1 folds for n operands
  assert r.stdout.count("lang.grammar.dot.new,k,__k.") == 3


def test_banana_dot_method_stays_anon_immediate(ir):
  # right side `.hi(x)` is a METHOD (parens), not a banana operand -> anon-immediate, no fold
  src = "blockref foo(||)\n__main__:\n\tfoo(| a |).hi(x)\n"
  r = ir(src)
  assert ".hi,x)" in r.stdout                   # method call on the lifted lambda
  assert ".__dot__," not in r.stdout            # not the operator path


def test_banana_dot_multiline_inline_lift(ir):
  # a MULTILINE dot-chain is lowered in sugar: operand construction is HOISTED to module scope
  # (a real `define __<ctor>.<seq>.<k>` + `lang.grammar.dot.new` per operand, flushed at END -- mirroring
  # the single-line lambdalift arm, so target-stamping kinds construct legally), folded via .__dot__,
  # and only the `.__call__` run stays inline in the recipe.
  src = "blockref foo(||)\nblockref bar(||)\n__main__:\n  foo(|\n    a\n  |).bar(|\n    b\n  |)\n"
  r = ir(src)
  assert "define __foo." in r.stdout             # operands hoisted to module scope (real define, not inline $(eval))
  assert "$(eval define __foo." not in r.stdout  # NOT the old inline-eval form
  assert "$(call lang.grammar.dot.new," in r.stdout      # constructed at module scope (guarded)
  assert "lang.grammar.dot.op," in r.stdout              # folded via the dot dunder (guarded)
  assert "lang.grammar.dot.run," in r.stdout             # result invoked inline in the recipe (guarded)


# error handling: a `.`-chain must use anonymous ctor operands whose kind defines the operator.
_DOT_KINDS = "from cmk import constructor\nconstructor foo[| ${self}.x := 1 |]\nconstructor bar[| ${self}.y := 2 |]\n"


def test_banana_dot_undefined_operator_errors(cmk, tmp_path):
  # a kind with no __dot__ used in a chain surfaces a CLEAR cmk error (not an opaque make
  # "undefined variable ..__dot__" warning).
  f = tmp_path / "bad.cmk"
  f.write_text(_DOT_KINDS + "__main__:\n\tfoo(| a |).bar(| b |)\n")
  r = cmk("cmk", "run", str(f), cwd=tmp_path)
  assert not r.ok
  assert "dot (.) operator is undefined" in (r.stdout + r.stderr)


@pytest.mark.parametrize("spaced", [False, True], ids=["unspaced", "spaced"])
@pytest.mark.parametrize("op,char", [(".", None), ("/", "/"), ("|", "|")], ids=["dot", "div", "pipe"])
def test_banana_operator_chain_lowers_with_and_without_spaces(ir, op, char, spaced):
  # both `a<op>b` and `a <op> b` between named bananas lower to the same fold (the trigger + sugar
  # opener guard tolerate whitespace around the operator char).  `.` stays on the byte-identical 2-arg
  # `lang.grammar.dot.op`; `/`,`|` route through `lang.grammar.dot.op.tbl` with the RAW char (TABLE A maps it in make).
  lhs, rhs = ("dsl.jqlang(| .n |)", "dsl.jqlang(| .x |)") if spaced else ("dsl.jqlang(|.n|)", "dsl.jqlang(|.x|)")
  joiner = f" {op} " if spaced else op
  r = ir(f"from cmk import dsl\ndemo:\n\t{lhs}{joiner}{rhs}\n")
  if char is None:  # `.`
    assert "$(call lang.grammar.dot.op,$(__fold_" in r.stdout and "lang.grammar.dot.op.tbl" not in r.stdout, r.stdout
  else:
    assert "lang.grammar.dot.op.tbl" in r.stdout and f",{char})" in r.stdout, r.stdout


def test_banana_chain_with_stdin_prefix_folds(ir):
  # a `<cmd> | <banana chain>` recipe feeds the chain's stdin: the pipe-terminated prefix is kept as LEAD
  # and the banana chain still folds (`lang.grammar.dot.run`).  Here io.json_builder pipes {n:4} into a jqlang pipe.
  r = ir("import io\nfrom cmk import dsl\ndemo:\n\tio.json_builder(n:raw=4) | dsl.jqlang(| .n |) | dsl.jqlang(| .+1 |)\n")
  assert "lang.grammar.dot.run" in r.stdout and "io.json_builder" in r.stdout, r.stdout + r.stderr


def test_banana_dot_named_instance_in_chain_errors(cmk, tmp_path):
  # a NAMED `ctor name(| .. |)` (a module-level declaration) written mid-chain -> a clear
  # error naming the module-vs-recipe confusion, not a mangled `foo.inst` undefined var.
  f = tmp_path / "bad2.cmk"
  f.write_text(_DOT_KINDS + "__main__:\n\tfoo inst(| a |).bar(| b |)\n")
  r = cmk("cmk", "run", str(f), cwd=tmp_path)
  assert not r.ok
  assert "module-level declaration" in (r.stdout + r.stderr)


# --- fluent declaration chains (staged grammar, xfail) --------------------------------------------

_FLUENT_HDR = "from cmk import dockerfs, Dockerfile\n"
_FLUENT_IMG = "Dockerfile img(|\n  FROM alpine:3.21\n  RUN true\n|)\n"


@pytest.mark.covers_demo("dockerfs.cmk")
def test_declaration_chain_link_lowers_as_a_receiver_call(ir):
  # expected: receiver body kept, link lowered as a call on the receiver's member, link body kept
  src = "alpha one(|\n  body one\n|).beta(k=v)(|\n  body two\n|)\n"
  r = ir(src)
  assert "cmk-fault" not in r.stdout, r.stdout
  assert "body one" in r.stdout, r.stdout
  assert "$(call one.beta," in r.stdout, r.stdout
  assert "body two" in r.stdout, r.stdout
  assert "body two\n|)" not in r.stdout, r.stdout   # body plus delimiter leaking as raw text


@pytest.mark.xfail(
  strict=True,
  reason="TODO: anonymous ctor declaration with kwargs -- `dockerfs(bind=.. path=.. mode=..)(| .. |)` "
  "with no declared name.  The name in the named form is semantically unused (nothing references "
  "it; it only gives registration a def), so the parser should gensym it.  This is the kwargs "
  "sibling of the ctor-args gap `X(a,b)(| body |)` xfailed in test_dsl_machine_cmk.py.  Today the "
  "parser takes the ctor word itself as the block name and faults with `using/paren kwargs with "
  "no PREFIX constructor`.  If this xpasses, drop this marker and promote the form to the "
  "dockerfs suite.",
)
def test_anonymous_ctor_kwargs_declaration_lowers(ir):
  # expected: same lowering as the named form, with a compiler-chosen def name
  src = _FLUENT_HDR + _FLUENT_IMG + "dockerfs(bind=img path=/etc/g1 mode=+x)(|\n  hello\n|)\n"
  r = ir(src)
  assert "cmk-fault" not in r.stdout, r.stdout
  assert "$(call dockerfs, def=" in r.stdout and "bind=img" in r.stdout, r.stdout


def test_recipe_chain_link_keeps_its_body(ir):
  # a link's body is hoisted as a gensym def and handed to the receiver call the way a ctor takes one
  src = "probe:\n  alpha(| body one |).beta(k=v)(| chain_body_marker |)\n"
  r = ir(src)
  assert "cmk-fault" not in r.stdout, r.stdout
  assert "chain_body_marker" in r.stdout, r.stdout
  assert "def=" in r.stdout, r.stdout


@pytest.mark.xfail(
  strict=True,
  reason="TODO: the paren-extractor that reads leading-paren ctor kwargs is not paren-balanced, so "
  "a value holding a make reference ends the kwargs early and the whole declaration falls through "
  "the scanner: it reaches the makefile verbatim, delimiters included, with no define and no ctor "
  "call.  Same leakage family as the chain-link specs above, and the same machinery a chain link "
  "must scan, since a link has to find the end of its kwargs before the body that follows.  The "
  "paren-safe workaround is body kwargs.  End-to-end consumer coverage lives in "
  "test_mint_kwargs_paren_cmk.py; this is the ctor-agnostic min-repro.  If this xpasses, the "
  "extractor learned balanced parens -- drop both markers.",
)
def test_leading_paren_kwargs_survive_a_make_reference(ir):
  # expected: the declaration mints, rather than reaching the output as raw source
  src = "alpha one(k=$(FOO) j=plain)(|\n  body one\n|)\n"
  r = ir(src)
  assert "$(call alpha," in r.stdout, r.stdout
  assert "body one" in r.stdout, r.stdout
  assert "alpha one(k=" not in r.stdout, r.stdout   # the declaration leaking as raw text
