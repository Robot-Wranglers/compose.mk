"""Compiler suite (low-hanging fruit): pure CMK->Makefile transforms.

The CMK transpile pipeline (mk.compile, mk.preprocess.*) is local awk/sed -
pure stdin->stdout, no docker. These assert *containment* of key transforms
rather than byte-exact golden output (compiled output carries a context header,
an `__interpreting__=` shebang, and a trailing NUL; golden tests deferred).

Heavier pieces deferred: mk.compile!/mk.interpret (embed/run), curated .cmk/.mk
behavioral twins, and full golden snapshots.
"""

import pytest

pytestmark = pytest.mark.compiler


def test_mk_compile_dialect(cmk):
  # Default dialect maps `this.` -> `${make} ` across the full pipeline.
  r = cmk("mk.compile", stdin="x:\n\tthis.y\n")
  assert r.ok, r.stderr
  assert "${make} y" in r.stdout


def test_mk_preprocess_dialect(cmk):
  r = cmk("mk.preprocess.dialect", stdin="x:\n\tthis.y\n")
  assert r.ok, r.stderr
  assert "${make} y" in r.stdout


def test_mk_preprocess_minify_strips_comments(cmk):
  r = cmk("mk.preprocess.minify", stdin="# a comment\nfoo:\n\t@true\n")
  assert r.ok, r.stderr
  assert "# a comment" not in r.stdout
  assert "foo:" in r.stdout


def test_mk_preprocess_decorators_passthrough(cmk):
  # Plain input (no decorators) passes through unchanged.
  r = cmk("mk.preprocess.decorators", stdin="foo:\n\t@true\n")
  assert r.ok, r.stderr
  assert "foo:" in r.stdout


# --- piecewise stage transforms (Stage 5-PRE regression net) -----------------
# The compile pipeline is a chain of independent stages (minify -> decorators ->
# dialect -> sugar -> .awk.main.preprocess -> .awk.dispatch). The tests above +
# below pin each *stage's* transform in isolation via its target, so the planned
# pipeline refactor (Stage 5: macros + fused fast path / flux.pipeline debug
# path) is provably behavior-preserving stage-by-stage -- not just end-to-end.
# All pure stdin->stdout (no docker). Stage boundaries are non-obvious: e.g. `⧐`
# and `this.` are *dialect* rules; the block glyphs (⋘⫻⟦🞹⨖) are *sugar*.


def test_stage_minify_zips_continuations(cmk):
  # `.awk.zip.linefeeds`: a `\`-continued recipe line is joined into one.
  r = cmk("mk.preprocess.minify", stdin="a:\n\tfoo \\\n\tbar\n")
  assert r.ok, r.stderr
  assert "foo bar" in r.stdout


def test_stage_minify_strips_docstrings(cmk):
  # `@#` docstring lines are dropped; the real recipe survives.
  r = cmk("mk.preprocess.minify", stdin="x:\n\t@# doc here\n\techo hi\n")
  assert r.ok, r.stderr
  assert "doc here" not in r.stdout
  assert "echo hi" in r.stdout


def test_stage_minify_preserves_define_block(cmk):
  # Inside define...endef, line-continuations are NOT zipped (raw block).
  r = cmk(
    "mk.preprocess.minify",
    stdin="define blk\nfoo \\\nbar\nendef\nx:\n\t@true\n",
  )
  assert r.ok, r.stderr
  assert "foo \\\nbar" in r.stdout  # continuation preserved in the block


def test_stage_decorators_relocate_above_target(cmk):
  # A `ᝏ` decorator written ABOVE a target is relocated to be the target's
  # first recipe line (then joinbody chains it with the rest of the body).
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏcompose.bind.target(debian)\nt:\n\techo hi\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\tᝏcompose.bind.target(debian)\n\techo hi" in r.stdout


def test_stage_decorators_inline_form_errors(cmk):
  # The old inline form (`target: ᝏ...`) is no longer supported.
  r = cmk(
    "mk.preprocess.decorators", stdin="t: ᝏcompose.bind.target(x)\n\techo hi\n"
  )
  assert not r.ok
  assert "no longer supported" in r.stderr


def test_stage_decorators_require_adjacent_target(cmk):
  # A blank line between the decorator and the target is rejected.
  r = cmk(
    "mk.preprocess.decorators", stdin="ᝏargs.from_json(s)\n\nt:\n\techo hi\n"
  )
  assert not r.ok
  assert "immediately above a target" in r.stderr


def test_stage_dialect_glyph_substitutions(cmk):
  # Default dialect maps the inline glyphs (⧐ -> .dispatch/, 🡄 -> ${jb}).
  r = cmk("mk.preprocess.dialect", stdin="r: svc⧐t\ne:\n\t🡄 k=v\n")
  assert r.ok, r.stderr
  assert "svc.dispatch/t" in r.stdout
  assert "${jb} k=v" in r.stdout


def test_stage_dialect_custom_hint(cmk):
  # A custom dialect (as would come from a `# cmk_dialect ::: … :::` header,
  # surfaced via the cmk_dialect env) replaces tokens outside define blocks.
  r = cmk(
    "mk.preprocess.dialect",
    stdin="x:\n\tfoo\n",
    env={"cmk_dialect": '[["foo","BAZ"]]'},
  )
  assert r.ok, r.stderr
  assert "BAZ" in r.stdout


def test_stage_dialect_preserves_define_block(cmk):
  # Glyphs inside define...endef are NOT rewritten; only outside.
  r = cmk(
    "mk.preprocess.dialect",
    stdin="define blk\nthis.literal\nendef\nx:\n\tthis.y\n",
  )
  assert r.ok, r.stderr
  assert "this.literal" in r.stdout  # inside: preserved
  assert "${make} y" in r.stdout  # outside: expanded


def test_stage_sugar_block_lowering(cmk):
  # Sugar handles the block glyphs: ⋘ NAME … ⋙ -> compose.import.string.
  r = cmk("mk.preprocess.sugar", stdin="⋘ mylib\nservices: {}\n⋙\n")
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


def _run_cmk(cmk, project, src):
  """Compile CMK ``src`` and run its ``__main__`` via plain ``make``."""
  compiled = cmk("mk.compile", stdin=src)
  assert compiled.ok, compiled.stderr
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


def test_interpret_dialect_chain(cmk, project):
  # `this.<t>` (dialect for `${make} <t>`) drives a multi-target run.
  r = _run_cmk(
    cmk,
    project,
    "a:\n\tprintf one\nb:\n\tprintf two\n__main__:\n\tthis.a; this.b\n",
  )
  assert r.ok, r.stderr
  assert "one" in r.stdout and "two" in r.stdout


def test_interpret_jq_extract(cmk, project):
  # `🡆` (dialect for `${stream.stdin} | ${jq} -r`) extracts a key. Pure (jq).
  r = _run_cmk(
    cmk,
    project,
    "consume:\n\t🡆 .key\n"
    '__main__:\n\techo \'{"key":"VALUE-X"}\' | this.consume\n',
  )
  assert r.ok, r.stderr
  assert "VALUE-X" in r.stdout


@pytest.mark.needs_docker
def test_interpret_structured_io_jb(cmk, project):
  # Full structured-IO: `🡄`(jb, containerized) emits JSON, `🡆`(jq) reads it.
  r = _run_cmk(
    cmk,
    project,
    "emit:\n\t🡄 key=val\nconsume:\n\t🡆 .key\n"
    "__main__:\n\tthis.emit | this.consume\n",
  )
  assert r.ok, r.stderr
  assert "val" in r.stdout


# --- functional idioms: pure (compile + run __main__, no docker) -------------
# More CMK idioms exercised end-to-end via _run_cmk. Inspired by demos/cmk/*
# (this./jq/host-script/code-import/decorators); all headless, no docker.


def test_interpret_this_with_arg(cmk, project):
  # `this.<t>/<arg>` dispatches a pattern target with a parameter.
  r = _run_cmk(
    cmk,
    project,
    'greet/%:\n\tprintf "hi $*"\n__main__:\n\tthis.greet/world\n',
  )
  assert r.ok, r.stderr
  assert "hi world" in r.stdout


def test_interpret_jq_nested(cmk, project):
  # `🡆 .a.b` extracts a nested key (dialect -> stream.stdin | jq -r).
  r = _run_cmk(
    cmk,
    project,
    "consume:\n\t🡆 .a.b\n"
    '__main__:\n\techo \'{"a":{"b":"DEEP"}}\' | this.consume\n',
  )
  assert r.ok, r.stderr
  assert "DEEP" in r.stdout


def test_interpret_host_script_import(cmk, project):
  # compose.import.script(def=...) imports a define-block as a host target
  # (script-dispatch-host idiom); runs locally, no container.
  r = _run_cmk(
    cmk,
    project,
    "define script.sh\n"
    'printf "SCRIPT-RAN\\n"\n'
    "endef\n"
    "compose.import.script(def=script.sh)\n"
    "__main__: script.sh\n",
  )
  assert r.ok, r.stderr
  assert "SCRIPT-RAN" in r.stdout


def test_interpret_code_block_to_file(cmk, project):
  # `🞹 <name> ... 🞹` (compose.import.code) yields a generated
  # `<name>.to.file/<f>` that writes the code-block to a file. Pure.
  r = _run_cmk(
    cmk,
    project,
    "🞹 mycode\nLINE-IN-CODE\n🞹\n__main__:\n\tthis.mycode.to.file/out.txt\n",
  )
  assert r.ok, r.stderr
  assert "LINE-IN-CODE" in (project.dir / "out.txt").read_text()


def test_interpret_call_sugar(cmk, project):
  # `cmk.x(args)` lowers to `$(call x,args)`; cmk.log.target logs the marker.
  r = _run_cmk(cmk, project, "__main__:\n\tcmk.log.target(MARKER-LOG)\n")
  assert r.ok, r.stderr
  assert "MARKER-LOG" in r.stdout + r.stderr


def test_interpret_comments_minified(cmk, project):
  # Comments are stripped by minify; the program still runs.
  r = _run_cmk(
    cmk,
    project,
    "# a comment\n# another\na:\n\tprintf one\n__main__:\n\tthis.a\n",
  )
  assert r.ok, r.stderr
  assert "one" in r.stdout


def test_interpret_decorator_args_from_json(cmk, project):
  # `ᝏargs.from_json(...)` ABOVE a target: parse JSON stdin into vars, filling
  # defaults for absent keys (kwarg-parsing idiom). The recipe body is TWO lines
  # and BOTH must see the bound vars -- i.e. the decorator + body share one shell
  # (the multi-line bug the above-form + joinbody fixes).
  src = (
    "ᝏargs.from_json(shape color=blue name=default)\n"
    "consume:\n"
    '\tprintf "1:shape=$${shape} color=$${color}\\n"\n'
    '\tprintf "2:name=$${name}\\n"\n'
    '__main__:\n\techo \'{"shape":"triangle"}\' | this.consume\n'
  )
  r = _run_cmk(cmk, project, src)
  assert r.ok, r.stderr
  assert "1:shape=triangle color=blue" in r.stdout
  assert (
    "2:name=default" in r.stdout
  )  # 2nd recipe line also sees the bound var


# --- functional idioms: transpilation of sugar blocks / glyphs (compile-only)
# These idioms need heavy interpreters/containers to *run*, so we assert the
# (pure, deterministic) transpilation instead -- the language-level behavior.


def test_compile_sugar_compose_string(cmk):
  r = cmk("mk.compile", stdin="⋘ mylib\nservices: {}\n⋙\n")
  assert r.ok, r.stderr
  assert "compose.import.string" in r.stdout and "def=mylib" in r.stdout


def test_compile_sugar_docker_def(cmk):
  r = cmk("mk.compile", stdin="⫻ myimg\nFROM alpine\n⫻\n")
  assert r.ok, r.stderr
  assert "docker.import.def" in r.stdout and "def=myimg" in r.stdout


def test_compile_sugar_code_import(cmk):
  r = cmk("mk.compile", stdin="🞹 mycode\nprint(1)\n🞹\n")
  assert r.ok, r.stderr
  assert "compose.import.code" in r.stdout and "def=mycode" in r.stdout


def test_compile_sugar_polyglot(cmk):
  r = cmk("mk.compile", stdin="⟦ hw\ncode\n⟧ with img as container\n")
  assert r.ok, r.stderr
  assert "polyglot" in r.stdout and "hw" in r.stdout


def test_compile_sugar_script_block(cmk):
  r = cmk(
    "mk.compile",
    stdin="⨖ scr\necho hi\n⨖ with alpine as compose_context\n",
  )
  assert r.ok, r.stderr
  assert "scr:" in r.stdout and "call" in r.stdout


def test_compile_dispatch_glyph_and_call(cmk):
  # `⧐` and `.dispatch(x)` both lower to `.dispatch/x`.
  assert (
    "svc.dispatch/target"
    in cmk("mk.compile", stdin="run: svc⧐target\n").stdout
  )
  assert (
    "svc.dispatch/target"
    in cmk("mk.compile", stdin="run: svc.dispatch(target)\n").stdout
  )


def test_compile_decorator(cmk):
  # `ᝏ<deco>(args)` above a target -> `cmk.bind.<deco>` -> `$(call bind.<deco>,args)`
  # as the target's first recipe line.
  r = cmk("mk.compile", stdin="ᝏcompose.bind.target(debian)\nt:\n")
  assert r.ok, r.stderr
  assert "$(call bind.compose.bind.target,debian)" in r.stdout


def test_compile_decorator_log_target(cmk):
  # `bind.log.target` lets log.target be a decorator (with a message).
  r = cmk("mk.compile", stdin="ᝏlog.target(starting)\nt:\n\tcmd\n")
  assert r.ok, r.stderr
  assert "$(call bind.log.target,starting)" in r.stdout


def test_compile_decorator_bare_no_parens(cmk):
  # A bare decorator (no `()`) behaves like an empty call: both lower the same.
  bare = cmk("mk.compile", stdin="ᝏlog.target\nt:\n\tcmd\n")
  empty = cmk("mk.compile", stdin="ᝏlog.target()\nt:\n\tcmd\n")
  assert bare.ok and empty.ok, bare.stderr
  assert "$(call bind.log.target,)" in bare.stdout
  assert "$(call bind.log.target,)" in empty.stdout


def test_interpret_decorator_log_target(cmk, project):
  # log.target as a decorator: it logs (stderr) and returns 0, so the body runs.
  src = (
    "ᝏlog.target(starting)\n"
    "build:\n\tprintf 'BODY1\\n'\n\tprintf 'BODY2\\n'\n"
    "__main__: build\n"
  )
  r = _run_cmk(cmk, project, src)
  assert r.ok, r.stderr
  assert (
    "BODY1" in r.stdout and "BODY2" in r.stdout
  )  # decorator returned 0; body ran
  assert "starting" in (r.stdout + r.stderr)  # the message was logged


def test_compile_call_sugar(cmk):
  r = cmk("mk.compile", stdin="compose.import(file=x.yml)\n")
  assert r.ok, r.stderr
  assert "$(call compose.import" in r.stdout and "file=x.yml" in r.stdout


def test_compile_inlines_import_target(cmk, tmp_path):
  # `mk.import.target(s)(..)` is resolved + INLINED at compile-time (the block is
  # baked into the output), not deferred to a runtime `$(call mk.import.*)`.
  (tmp_path / "src.mk").write_text("greet:\n\t@echo hi\n")
  r = cmk("mk.compile", stdin="mk.import.targets(file=src.mk target=greet)\n")
  assert r.ok, r.stderr
  assert "$(call mk.import" not in r.stdout  # not deferred to runtime
  assert "greet:" in r.stdout  # block inlined verbatim
  assert "@echo hi" in r.stdout


def test_compile_inlines_import_def(cmk, tmp_path):
  # likewise for define-blocks: inlined as a fresh `define ... endef`.  (The def
  # source must `include compose.mk` -- the importer reads via `mk.def.read`.)
  from pathlib import Path

  compose_mk = Path(__file__).resolve().parent.parent / "compose.mk"
  (tmp_path / "src.mk").write_text(
    f"include {compose_mk}\ndefine greeting\nhello world\nendef\n"
  )
  r = cmk("mk.compile", stdin="mk.import.def(file=src.mk def=greeting)\n")
  assert r.ok, r.stderr
  assert "$(call mk.import" not in r.stdout
  assert "define greeting" in r.stdout
  assert "hello world" in r.stdout


def test_compile_jb_glyph(cmk):
  assert "${jb}" in cmk("mk.compile", stdin="e:\n\t🡄 k=v\n").stdout


def test_compile_dialect_preserves_define_block(cmk):
  # Glyphs inside define...endef are NOT rewritten -- only outside.
  r = cmk(
    "mk.compile",
    stdin="define blk\nthis.literal\nendef\nx:\n\tthis.y\n",
  )
  assert r.ok, r.stderr
  assert "${make} y" in r.stdout  # outside the block: expanded
  assert "this.literal" in r.stdout  # inside the block: preserved


# --- the `⇐` assignment operator --------------------------------------------
# `LHS ⇐ RHS` -> ``LHS=`RHS` ``, capturing RHS up to the next shell separator.
# Runs after the dialect pass, so `this.y` is already `${make} y` here.


def test_compile_assign_basic(cmk):
  r = cmk("mk.compile", stdin="x ⇐ this.y\n")
  assert r.ok, r.stderr
  assert "x=`${make} y`" in r.stdout


def test_compile_assign_leaves_tail_intact(cmk):
  # capture stops at the `;`; the rest of the line is preserved.
  r = cmk("mk.compile", stdin="x ⇐ this.y ; echo done\n")
  assert r.ok, r.stderr
  assert "x=`${make} y" in r.stdout and "`; echo done" in r.stdout


def test_compile_assign_multiple_per_line(cmk):
  r = cmk("mk.compile", stdin="y ⇐ this.a; x ⇐ this.b\n")
  assert r.ok, r.stderr
  assert "y=`${make} a`; x=`${make} b`" in r.stdout


def test_compile_assign_stops_at_logical_and(cmk):
  # `&&` terminates the captured command (the common `x=`cmd` && more` shape).
  r = cmk("mk.compile", stdin="body ⇐ ${jq} . && more\n")
  assert r.ok, r.stderr
  assert "body=`${jq} ." in r.stdout and "`&& more" in r.stdout


def test_compile_assign_captures_pipeline(cmk):
  # A single `|` is NOT a separator (only `;`/`&&`/`||` are), so a whole pipeline
  # is captured: `x ⇐ this.one | this.two` -> ``x=`${make} one | ${make} two` ``.
  r = cmk("mk.compile", stdin="x ⇐ this.one | this.two\n")
  assert r.ok, r.stderr
  assert "x=`${make} one | ${make} two`" in r.stdout


def test_compile_assign_skips_define_block(cmk):
  # `⇐` inside define...endef is left verbatim.
  r = cmk("mk.compile", stdin="define blk\nx ⇐ this.y\nendef\n")
  assert r.ok, r.stderr
  assert "x ⇐ this.y" in r.stdout


def test_compile_assign_triplequote(cmk):
  # assignment + triple-quote compose: the triple-quote lowers to a `printf`
  # first, then `⇐` captures it -> a shell var holding the literal text.
  r = cmk("mk.compile", stdin="x ⇐ '''foo bar'''\n")
  assert r.ok, r.stderr
  assert "x=`printf '%s' 'foo bar'`" in r.stdout


# --- triple-quote literals ('''…''' / """…""") ------------------------------
# Lower to a literal, %-safe `printf '%s' '…'` (multi-line: '%s\n%s…').


def test_compile_triplequote_basic_pipe(cmk):
  r = cmk("mk.compile", stdin="'''foo bar''' | this.t\n")
  assert r.ok, r.stderr
  assert "printf '%s' 'foo bar' | ${make} t" in r.stdout


def test_compile_triplequote_internal_double_quote(cmk):
  r = cmk("mk.compile", stdin="'''say \"hi\"'''\n")
  assert r.ok, r.stderr
  assert "printf '%s' 'say \"hi\"'" in r.stdout


def test_compile_triplequote_internal_single_quote(cmk):
  # `"""…"""` delimiter lets the content hold a single quote; it's escaped '\''.
  r = cmk("mk.compile", stdin='"""it\'s"""\n')
  assert r.ok, r.stderr
  assert "printf '%s' 'it'\\''s'" in r.stdout


def test_compile_triplequote_percent_is_literal(cmk):
  # `%` is an ARG to `%s`, so it stays literal (a win over raw `printf 'TEXT'`).
  r = cmk("mk.compile", stdin="'''100%done'''\n")
  assert r.ok, r.stderr
  assert "printf '%s' '100%done'" in r.stdout


def test_compile_triplequote_multiline(cmk):
  # spans lines -> one printf with '%s\n%s' and per-line args.
  r = cmk("mk.compile", stdin="x:\n\t'''L1\nL2''' | this.t\n")
  assert r.ok, r.stderr
  assert "printf '%s\\n%s' 'L1' 'L2' | ${make} t" in r.stdout


def test_compile_triplequote_skips_define_block(cmk):
  # python-style '''docstrings''' inside define...endef pass through verbatim.
  r = cmk("mk.compile", stdin="define blk\nx = '''doc'''\nendef\n")
  assert r.ok, r.stderr
  assert "x = '''doc'''" in r.stdout


# --- recipe-body joining (.awk.joinbody) ------------------------------------
# The newline-separated lines of a recipe body are joined into ONE shell with
# ` && \` (shared state, fail-fast).


def test_compile_joinbody_basic(cmk):
  r = cmk("mk.compile", stdin="x:\n\tcmd1\n\tcmd2\n")
  assert r.ok, r.stderr
  assert "cmd1 && \\\n" in r.stdout
  assert "\tcmd2" in r.stdout


def test_compile_joinbody_keeps_trailing_connector(cmk):
  # a line already ending in a connector just continues (no extra `&&`).
  r = cmk("mk.compile", stdin="x:\n\tcmd1 ;\n\tcmd2\n")
  assert r.ok, r.stderr
  assert "cmd1 ; \\\n" in r.stdout
  assert "cmd1 ; && " not in r.stdout


def test_compile_joinbody_prefix_stands_alone(cmk):
  # `-`/`+`-prefixed lines are not joined (make honors the prefix only at a
  # recipe-line start).
  r = cmk("mk.compile", stdin="x:\n\tcmd1\n\t-cmd2\n\tcmd3\n")
  assert r.ok, r.stderr
  assert "-cmd2" in r.stdout
  assert "cmd1 && \\" not in r.stdout  # cmd1 flushed before the -line
  assert "-cmd2 && \\" not in r.stdout  # -line not joined into cmd3


def test_compile_joinbody_single_line_unchanged(cmk):
  r = cmk("mk.compile", stdin="x:\n\tonly\n")
  assert r.ok, r.stderr
  assert "\tonly" in r.stdout
  assert "only && \\" not in r.stdout


def test_compile_joinbody_explicit_continuation(cmk):
  # minify zips the `\`-continued `a`+`b` into one command; joinbody adds ` && `
  # only before the separate `c` -- never between `a` and `b`.
  r = cmk("mk.compile", stdin="x:\n\ta \\\n\tb\n\tc\n")
  assert r.ok, r.stderr
  assert "a b && \\\n" in r.stdout
  assert "\tc" in r.stdout


def test_compile_joinbody_skips_define_block(cmk):
  # define...endef bodies (polyglot/awk) are not joined.
  r = cmk("mk.compile", stdin="define blk\nl1\nl2\nendef\n")
  assert r.ok, r.stderr
  assert "l1\nl2" in r.stdout
  assert "l1 && \\" not in r.stdout
