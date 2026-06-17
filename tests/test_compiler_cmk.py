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
# All pure stdin->stdout (no docker). Stage boundaries are non-obvious: e.g. `ᐉ`
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


def test_stage_decorators_postfix_after_body(cmk):
  # `postfix_mode=&&` relocates the decorator to AFTER the body; the last body
  # line gains a trailing `&&` so joinbody chains `body && decorator`.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(postfix_mode=&&)\nt:\n\techo a\n\techo b\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\techo a\n\techo b &&\n\tᝏmark()" in r.stdout


def test_stage_decorators_postfix_connectors(cmk):
  # The kwarg value IS the shell connector: `;` (always) and `||` (on failure).
  semi = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(postfix_mode=;)\nt:\n\techo body\n",
  )
  assert semi.ok, semi.stderr
  assert "echo body ;\n\tᝏmark()" in semi.stdout
  orr = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(postfix_mode=||)\nt:\n\techo body\n",
  )
  assert orr.ok, orr.stderr
  assert "echo body ||\n\tᝏmark()" in orr.stdout


def test_stage_decorators_postfix_strips_kwarg_from_args(cmk):
  # `postfix_mode` is a compiler directive, stripped before the macro call; the
  # decorator's real args survive untouched.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(realarg, postfix_mode=&&)\nt:\n\techo b\n",
  )
  assert r.ok, r.stderr
  assert "ᝏmark(realarg)" in r.stdout
  assert "postfix_mode" not in r.stdout


def test_stage_decorators_postfix_mixed_with_prefix(cmk):
  # A target may carry both: prefix decorators stay at the head, postfix at the
  # tail (`prefix && body || postfix`).
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏpre(x)\nᝏpost(postfix_mode=||)\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "t:\n\tᝏpre(x)\n\techo body ||\n\tᝏpost()" in r.stdout


def test_stage_decorators_postfix_space_indented_body(cmk):
  # Space-indented bodies work too: body lines are re-emitted verbatim (the
  # indent stage normalises them later), only the decorator line gets a tab.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(postfix_mode=;)\nt:\n    echo body\n",
  )
  assert r.ok, r.stderr
  assert "    echo body ;\n\tᝏmark()" in r.stdout


def test_stage_decorators_postfix_invalid_mode_errors(cmk):
  # An unrecognised connector is a compile error.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="ᝏmark(postfix_mode=foo)\nt:\n\techo b\n",
  )
  assert not r.ok
  assert "postfix_mode must be one of" in r.stderr


def test_stage_decorators_postfix_default_mode(cmk):
  # A `bind.<name>.postfix_mode := <conn>` companion declaration makes a BARE
  # `ᝏ<name>` postfix without repeating the kwarg on every use.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="bind.g.postfix_mode := ||\nᝏg\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "echo body ||\n\tᝏg()" in r.stdout


def test_stage_decorators_postfix_explicit_overrides_default(cmk):
  # An explicit kwarg still wins over the declared default.
  r = cmk(
    "mk.preprocess.decorators",
    stdin="bind.g.postfix_mode := ||\nᝏg(postfix_mode=;)\nt:\n\techo body\n",
  )
  assert r.ok, r.stderr
  assert "echo body ;\n\tᝏg()" in r.stdout


def test_stage_dialect_glyph_substitutions(cmk):
  # Default dialect maps the inline glyphs (ᐉ -> .dispatch/, 🡄 -> ${jb}).
  r = cmk("mk.preprocess.dialect", stdin="r: svcᐉt\ne:\n\t🡄 k=v\n")
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
  # The `⫻` sugar lowers to `docker.import` (def=/file= routed internally);
  # `docker.import.def` is now a deprecated alias.
  assert "docker.import" in r.stdout and "def=myimg" in r.stdout


def test_compile_sugar_code_import(cmk):
  r = cmk("mk.compile", stdin="🞹 mycode\nprint(1)\n🞹\n")
  assert r.ok, r.stderr
  assert "compose.import.code" in r.stdout and "def=mycode" in r.stdout


def test_compile_sugar_polyglot(cmk):
  # The `with` clause is space-separated kwargs (the positional comma form is
  # retired); they forward verbatim into the lowered polyglot.import call.
  r = cmk(
    "mk.compile",
    stdin="⟦ hw\ncode\n⟧ with img=alp entrypoint=sh as container\n",
  )
  assert r.ok, r.stderr
  assert "polyglot" in r.stdout and "hw" in r.stdout
  assert "img=alp entrypoint=sh" in r.stdout


def test_compile_sugar_polyglot_parenthetical(cmk):
  # An optional parenthetical may wrap the with-clause for readability:
  # `with (kwargs) as X` lowers identically to `with kwargs as X`.
  r = cmk(
    "mk.compile",
    stdin="⟦ hw\ncode\n⟧ with (img=alp entrypoint=sh) as container\n",
  )
  assert r.ok, r.stderr
  assert "img=alp entrypoint=sh" in r.stdout
  assert "(img=alp" not in r.stdout  # the wrapping parens were stripped


def test_compile_sugar_script_block(cmk):
  r = cmk(
    "mk.compile",
    stdin="⨖ scr\necho hi\n⨖ with img=alpine as compose_context\n",
  )
  assert r.ok, r.stderr
  assert "scr:" in r.stdout and "call" in r.stdout
  assert "img=alpine" in r.stdout


def test_compile_advice_interrupted_next_line(cmk):
  # "Interrupted advice": the `with .. as ..` trailer may spill onto the line
  # AFTER the close marker (bare line-feed, no `\` needed).
  r = cmk(
    "mk.compile",
    stdin="⨖ scr\necho hi\n⨖\nwith img=alpine as compose_context\n",
  )
  assert r.ok, r.stderr
  assert "scr:" in r.stdout and "img=alpine" in r.stdout
  assert "compose_context" in r.stdout


def test_compile_advice_interrupted_split(cmk):
  # `with` on the close line, `as` continued on the next line.
  r = cmk(
    "mk.compile",
    stdin="⨖ scr\necho hi\n⨖ with img=alpine\nas compose_context\n",
  )
  assert r.ok, r.stderr
  assert "scr:" in r.stdout and "img=alpine" in r.stdout
  assert "compose_context" in r.stdout


def test_compile_advice_interrupted_blank_then_advice(cmk):
  # Blank line(s) between the close marker and the advice are skipped.
  r = cmk(
    "mk.compile",
    stdin="⨖ scr\necho hi\n⨖\n\nwith img=alpine as compose_context\n",
  )
  assert r.ok, r.stderr
  assert "scr:" in r.stdout and "img=alpine" in r.stdout
  assert "compose_context" in r.stdout


def test_compile_advice_interrupted_does_not_eat_next_block(cmk):
  # A non-advice line after a bare close (here the next block's open marker) is
  # re-dispatched normally -- the second block must still open.
  r = cmk(
    "mk.compile",
    stdin="⨖ a\necho hi\n⨖\n⨖ b\necho bye\n⨖ with img=alpine as compose_context\n",
  )
  assert r.ok, r.stderr
  assert "define a" in r.stdout and "define b" in r.stdout
  assert "a:;" in r.stdout and "b:;" in r.stdout


def test_compile_advice_interrupted_keyword_guard(cmk):
  # `with`/`as` matching is keyword-anchored: an ordinary target line after a
  # bare close (e.g. `with_deps:`) is NOT mistaken for advice.
  r = cmk("mk.compile", stdin="⨖ scr\necho hi\n⨖\nwith_deps: foo\n")
  assert r.ok, r.stderr
  assert "with_deps: foo" in r.stdout


def test_compile_sugar_module(cmk):
  # `⦖ NAME … ⦕` -> `define NAME … endef` + a chain to mk.import.module(def=NAME).
  r = cmk("mk.compile", stdin="⦖ mymod\nFOO := 1\n⦕\n")
  assert r.ok, r.stderr
  assert "define mymod" in r.stdout
  assert "endef" in r.stdout
  assert "mk.import.module" in r.stdout and "def=mymod" in r.stdout


def test_compile_sugar_module_as(cmk):
  # `⦖ NAME … ⦕ as alias` -> the `as` clause becomes namespace=alias.
  r = cmk("mk.compile", stdin="⦖ mod\nFOO := 1\n⦕ as alias\n")
  assert r.ok, r.stderr
  assert "def=mod" in r.stdout and "namespace=alias" in r.stdout


def test_compile_sugar_module_with_as(cmk):
  # `⦖ NAME … ⦕ with PRE as alias` -> with-clause -> preprocs=, as-clause ->
  # namespace=.
  r = cmk("mk.compile", stdin="⦖ mod\nFOO := 1\n⦕ with PRE as alias\n")
  assert r.ok, r.stderr
  assert "namespace=alias" in r.stdout and "preprocs=PRE" in r.stdout


def test_compile_dispatch_glyph_and_call(cmk):
  # `ᐉ` and `.dispatch(x)` both lower to `.dispatch/x`.
  assert (
    "svc.dispatch/target"
    in cmk("mk.compile", stdin="run: svcᐉtarget\n").stdout
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


def test_compile_triplequote_double_is_interpolating(cmk):
  # `"""…"""` is the interpolating (DOUBLE-quoted) form: shell `$VAR`/`` `cmd` `` expand.
  r = cmk("mk.compile", stdin='"""$X"""\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"$X\"" in r.stdout


def test_compile_triplequote_double_internal_single_quote(cmk):
  # A literal single quote sits fine inside the double-quoted form (no escaping).
  r = cmk("mk.compile", stdin='"""it\'s"""\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"it's\"" in r.stdout


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


# --- triple-BACKTICK literals (```…```) -------------------------------------
# Like triple-quote, but DOUBLE-quoted -> standard interpolation (`cmds`, $vars).


def test_compile_triplebacktick_interpolating(cmk):
  # the distinguishing behavior: DOUBLE-quoted printf (vs triple-quote's single).
  r = cmk("mk.compile", stdin="```$X``` | this.t\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"$X\" | ${make} t" in r.stdout


def test_compile_triplebacktick_backtick_passthrough(cmk):
  # a command-sub inside survives verbatim (interpolated by the shell at runtime).
  r = cmk("mk.compile", stdin="```a`id`b```\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"a`id`b\"" in r.stdout


def test_compile_triplebacktick_escapes_double_quote(cmk):
  # an internal " is escaped so the double-quoted string stays well-formed.
  r = cmk("mk.compile", stdin='```say "hi"```\n')
  assert r.ok, r.stderr
  assert 'printf \'%s\' "say \\"hi\\""' in r.stdout


def test_compile_triplebacktick_multiline(cmk):
  r = cmk("mk.compile", stdin="x:\n\t```L1\nL2``` | this.t\n")
  assert r.ok, r.stderr
  assert 'printf \'%s\\n%s\' "L1" "L2" | ${make} t' in r.stdout


def test_compile_triplebacktick_content_ends_with_backtick(cmk):
  # The closer is the LAST 3 of a backtick run, so the content may end with a
  # backtick (e.g. a command-sub right before the close): ````id```` -> "`id`".
  r = cmk("mk.compile", stdin="````id````\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"`id`\"" in r.stdout


def test_compile_triplequote_still_literal(cmk):
  # regression: the single-quoted (literal) forms are unchanged by the backtick add.
  r = cmk("mk.compile", stdin="'''$X''' | this.t\n")
  assert r.ok, r.stderr
  assert "printf '%s' '$X' | ${make} t" in r.stdout


# --- callable targets: this.NAME(...) / this.NAME'''...''' (.awk.callable) ----
# The `callable` stage runs AFTER dialect (so `this.NAME` is already `${make} NAME`)
# and BEFORE triplequote; it relocates a target's argument into a stdin pipe and never
# lowers the literal itself.  Happy-path tests go through full `mk.compile`; error cases
# use the standalone stage target (`mk.preprocess.callable`, fed the post-dialect
# `${make} ` form) so the nonzero exit is observable -- the full pipe masks a mid-stage
# failure (same convention as the indent-stage tests below).


def test_callable_quoted_call(cmk):
  r = cmk("mk.compile", stdin="x:\n\tthis.eval('''(Hi)S''')\n")
  assert r.ok, r.stderr
  assert "printf '%s' '(Hi)S' | ${make} eval" in r.stdout


def test_callable_quoted_call_doublequote(cmk):
  # `"""…"""` is interpolating, so it lowers to a double-quoted printf.
  r = cmk("mk.compile", stdin='x:\n\tthis.eval("""(Hi)S""")\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"(Hi)S\" | ${make} eval" in r.stdout


def test_callable_quoted_call_backtick_interpolates(cmk):
  # the ``` delimiter is interpolating: lowers to a DOUBLE-quoted printf.
  r = cmk("mk.compile", stdin="x:\n\tthis.eval(```$X```)\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"$X\" | ${make} eval" in r.stdout


def test_callable_tagged(cmk):
  r = cmk("mk.compile", stdin="x:\n\tthis.eval'''(Hi)S'''\n")
  assert r.ok, r.stderr
  assert "printf '%s' '(Hi)S' | ${make} eval" in r.stdout


def test_callable_tagged_backtick(cmk):
  r = cmk("mk.compile", stdin="x:\n\tthis.eval```$X```\n")
  assert r.ok, r.stderr
  assert "printf '%s' \"$X\" | ${make} eval" in r.stdout


def test_callable_unquoted_pipes_command(cmk):
  # unquoted arg is moved verbatim (its stdout is piped in).
  r = cmk("mk.compile", stdin="x:\n\tthis.eval(cat f)\n")
  assert r.ok, r.stderr
  assert "cat f | ${make} eval" in r.stdout


def test_callable_chaining(cmk):
  # this.b(this.a) -> ${make} a | ${make} b (inner already lowered by dialect).
  r = cmk("mk.compile", stdin="x:\n\tthis.b(this.a)\n")
  assert r.ok, r.stderr
  assert "${make} a | ${make} b" in r.stdout


def test_callable_multiline_quoted(cmk):
  r = cmk("mk.compile", stdin="x:\n\tthis.eval('''L1\nL2''')\n")
  assert r.ok, r.stderr
  assert "printf '%s\\n%s' 'L1' 'L2' | ${make} eval" in r.stdout


def test_callable_subshell_arg(cmk):
  # a subshell argument is spanned by balanced parens and piped verbatim.
  r = cmk("mk.compile", stdin="x:\n\tthis.foo((echo a; echo b))\n")
  assert r.ok, r.stderr
  assert "(echo a; echo b) | ${make} foo" in r.stdout


def test_callable_not_a_call_semicolon_subshell(cmk):
  # `this.b; (this.a)` is plain shell, NOT a call -- must stay verbatim.
  r = cmk("mk.compile", stdin="x:\n\tthis.b; (this.a)\n")
  assert r.ok, r.stderr
  assert "${make} b; (${make} a)" in r.stdout
  assert "${make} a | ${make} b" not in r.stdout


def test_callable_not_a_call_space_before_paren(cmk):
  # a space between NAME and `(` means it's not a call.
  r = cmk("mk.compile", stdin="x:\n\tthis.foo (x)\n")
  assert r.ok, r.stderr
  assert "${make} foo (x)" in r.stdout


def test_callable_bare_this_unchanged(cmk):
  # bare this.foo (no adjacent (/delim) is an ordinary make invocation.
  r = cmk("mk.compile", stdin="x:\n\tthis.foo bar\n")
  assert r.ok, r.stderr
  assert "${make} foo bar" in r.stdout


def test_callable_skips_define_block(cmk):
  # inert inside define..endef (dialect/callable/triplequote all skip it).
  r = cmk("mk.compile", stdin="define blk\nthis.t('''x''')\nendef\n")
  assert r.ok, r.stderr
  assert "this.t('''x''')" in r.stdout


def test_callable_defers_dispatch_form(cmk):
  # `.dispatch(target)` is container dispatch (the .awk.dispatch pass), NOT a callable
  # pipe -- callable must leave names ending in `.dispatch` alone.
  r = cmk("mk.compile", stdin="x:\n\tthis.alice.dispatch(self.task)\n")
  assert r.ok, r.stderr
  assert "${make} alice.dispatch/self.task" in r.stdout
  assert "self.task | ${make}" not in r.stdout


def test_callable_error_unterminated_unquoted(cmk):
  r = cmk("mk.preprocess.callable", stdin="x:\n\t${make} t(a b\n")
  assert not r.ok
  assert "compose.mk (cmk:callable) error:" in r.stderr
  assert "unterminated" in r.stderr
  assert "at line" in r.stderr


def test_callable_error_unterminated_literal(cmk):
  r = cmk("mk.preprocess.callable", stdin="x:\n\t${make} t('''oops\n")
  assert not r.ok
  assert "unterminated triple-quoted literal" in r.stderr


def test_callable_error_mixed_content(cmk):
  r = cmk("mk.preprocess.callable", stdin="x:\n\t${make} t('''a''' more)\n")
  assert not r.ok
  assert "expected ')'" in r.stderr


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


# --- python-style indentation: space OR tab recipe bodies (mk.preprocess.indent) --
# The `indent` stage runs LAST in the preprocess chain (after sugar lowered its
# literal blocks to define..endef), normalizing a consistently SPACE-indented body
# to the leading tab Make needs, passing TAB bodies through verbatim, and erroring
# on mixed (tabs+spaces in one indent) or mismatched indentation. Error cases use
# the standalone stage target (`mk.preprocess.indent`) so the nonzero exit is
# observable -- the full `mk.compile` pipe masks a mid-pipe failure (same as the
# decorator-stage errors above); the real `mk.interpret!` path does surface it.


def test_compile_space_indented_recipe(cmk):
  # A space-indented recipe body compiles: spaces -> one leading tab, then joined.
  r = cmk("mk.compile", stdin="x:\n    cmd1\n    cmd2\n")
  assert r.ok, r.stderr
  assert (
    "cmd1 && \\\n" in r.stdout
  )  # joinbody saw it as a recipe (i.e. tab-led)
  assert "\tcmd2" in r.stdout  # normalized to a tab, not left as spaces
  assert "    cmd2" not in r.stdout  # the original spaces are gone


def test_indent_stage_normalizes_spaces_to_tab(cmk):
  # The stage itself rewrites leading spaces to a single tab.
  r = cmk("mk.preprocess.indent", stdin="x:\n    a\n    b\n")
  assert r.ok, r.stderr
  assert "\ta\n" in r.stdout and "\tb\n" in r.stdout
  assert "    a" not in r.stdout


def test_indent_stage_tab_body_unchanged(cmk):
  # Back-compat: tab-indented bodies pass through verbatim (incl. deeper tabs).
  r = cmk("mk.preprocess.indent", stdin="x:\n\ta\n\t\tb\n")
  assert r.ok, r.stderr
  assert "\ta\n" in r.stdout and "\t\tb\n" in r.stdout


def test_indent_stage_skips_define_block(cmk):
  # define..endef data (e.g. lowered sugar blocks: compose YAML) is verbatim.
  r = cmk("mk.preprocess.indent", stdin="define blk\n    raw spaces\nendef\n")
  assert r.ok, r.stderr
  assert "    raw spaces" in r.stdout  # NOT rewritten to a tab


def test_indent_mixed_tabs_and_spaces_errors(cmk):
  # A single indent that mixes a tab and spaces is rejected ("mixed mode").
  r = cmk("mk.preprocess.indent", stdin="x:\n\t  cmd\n")
  assert not r.ok
  assert "mixes tabs and spaces" in r.stderr


def test_indent_mismatched_spaces_errors(cmk):
  # Inconsistent space-indent within one body is rejected ("mismatched").
  r = cmk("mk.preprocess.indent", stdin="x:\n    cmd1\n  cmd2\n")
  assert not r.ok
  assert "inconsistent indentation" in r.stderr
