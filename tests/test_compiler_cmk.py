"""Compiler suite (low-hanging fruit): pure CMK->Makefile transforms.

The CMK transpile pipeline (mk.compile, mk.preprocess.*) is local awk/sed —
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
  # `ᝏargs.from_json(...)` decorates a target: parse JSON stdin into vars,
  # filling defaults for absent keys (kwarg-parsing idiom).
  src = (
    "consume: ᝏargs.from_json(shape color=blue name=default)\n"
    '\tprintf "shape=$${shape} color=$${color} name=$${name}\\n"\n'
    '__main__:\n\techo \'{"shape":"triangle"}\' | this.consume\n'
  )
  r = _run_cmk(cmk, project, src)
  assert r.ok, r.stderr
  assert "shape=triangle color=blue name=default" in r.stdout


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
  # `ᝏ<deco>(args)` -> `; cmk.bind.<deco>` -> `$(call bind.<deco>,args)`.
  r = cmk("mk.compile", stdin="t: ᝏcompose.bind.target(debian)\n")
  assert r.ok, r.stderr
  assert "bind.target" in r.stdout


def test_compile_call_sugar(cmk):
  r = cmk("mk.compile", stdin="compose.import(file=x.yml)\n")
  assert r.ok, r.stderr
  assert "$(call compose.import" in r.stdout and "file=x.yml" in r.stdout


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
