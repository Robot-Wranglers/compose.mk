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


# --- interpreter --------------------------------------------------------------
# `mk.interpret!` ends with mk.yield -> mk.interrupt, a SIGINT-based control
# transfer to the supervisor the standalone shebang installs. That works headless
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
# with ${make} recursion staying inside the compiled file. `project` supplies the
# compose.mk copy the include resolves against. The jb (structured-IO) case is
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
    'consume:\n\t🡆 .key\n__main__:\n\techo \'{"key":"VALUE-X"}\' | this.consume\n',
  )
  assert r.ok, r.stderr
  assert "VALUE-X" in r.stdout


@pytest.mark.needs_docker
def test_interpret_structured_io_jb(cmk, project):
  # Full structured-IO: `🡄`(jb, containerized) emits JSON, `🡆`(jq) reads it.
  r = _run_cmk(
    cmk,
    project,
    "emit:\n\t🡄 key=val\nconsume:\n\t🡆 .key\n__main__:\n\tthis.emit | this.consume\n",
  )
  assert r.ok, r.stderr
  assert "val" in r.stdout
