"""Integration tests for the public `cmk` subcommand interface (compose.mk).

`cmk` is a convenience front-end uniting several internal CMK workflows:

  cmk build <f> [bin]   -> lang.pkg            (self-extracting binary)  [needs_docker]
  cmk compile <f> [out] -> mk.compiler[!]    (transpile: preview | full standalone)
  cmk run <f> [args..]  -> mk.compile + mk.interpret/%   (compile + run)
  cmk <f> [args..]      -> same as `cmk run`
  cmk doc <f>           -> add a mode-matching shebang + chmod +x + compile-check

All subcommands rely on the supervisor's yield/interrupt epilogue to consume
their subcommand tail (so the words after `cmk` aren't treated as make goals);
hence every invocation sets CMK_SUPERVISOR=1 (the harness default is 0).

These run host-side and need no docker EXCEPT `build` (makeself). The tty-only
`compile` preview branch (pygmentize) is covered by manual verification; here we
exercise the full/redirect branch that a captured (non-tty) stdout naturally
takes.
"""

import os
import subprocess

import pytest

pytestmark = pytest.mark.integration

# A trivial CMK program: compiles + runs host-side (no docker), prints to stdout.
HELLO = "__main__:\n\techo CMK-RUN-OK\n"

# `cmk`'s single yield/interrupt needs the supervisor (harness default is 0).
SUP = {"CMK_SUPERVISOR": "1"}


# --- run ---------------------------------------------------------------------


def test_run(cmk, tmp_path):
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "run", "hello.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout


def test_run_bare_is_run(cmk, tmp_path):
  # bare `cmk <file>` is shorthand for `cmk run <file>`.
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "hello.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout


def test_run_with_continuation_args(cmk, tmp_path):
  # trailing args after the file become the program's make goals (continuation).
  (tmp_path / "hello.cmk").write_text(HELLO + "extra:\n\techo EXTRA-TARGET\n")
  r = cmk("cmk", "run", "hello.cmk", "extra", env=SUP)
  assert r.ok, r.stderr
  assert "EXTRA-TARGET" in r.stdout


# --- help / usage ------------------------------------------------------------


def test_help_shows_entrypoint_docstring(cmk):
  # `cmk help` prints the entrypoint's `@#` docstring as a description ABOVE the
  # generated subcommand list (build/compile/run/doc).
  r = cmk("cmk", "help", env=SUP)
  assert r.ok, r.stderr
  assert "Compile, run, package, and inspect" in r.stderr  # from cmk's @# docstring
  for sub in ("build", "compile", "run", "doc"):
    assert sub in r.stderr  # generated subcommand list


def test_help_summarizes_each_subcommand(cmk):
  # Each subcommand line carries the first docstring line of its handler.
  r = cmk("cmk", "help", env=SUP)
  assert r.ok, r.stderr
  assert "Compile and run a program." in r.stderr  # cli.cmk.run/%
  assert "Show the bare Makefile fragment" in r.stderr  # cli.cmk.transpile/%


def test_help_names_the_invocation(cmk):
  # A wrapper standing for `<program> cmk` says so via CMK_ARGV0, and usage follows.
  r = cmk("cmk", "help", env={**SUP, "CMK_ARGV0": "cmk"})
  assert r.ok, r.stderr
  assert "USAGE: cmk <subcommand>" in r.stderr


# --- guards (cross-cutting file hygiene) -------------------------------------


def test_missing_input_fails(cmk):
  r = cmk("cmk", "run", "nope.cmk", env=SUP)
  assert not r.ok
  assert "no such file" in r.stderr.lower()


def test_run_non_cmk_extension_is_quiet(cmk, tmp_path):
  # a non-.cmk input still runs; but `cmk run` is a direct/__main__ invocation and
  # forces CMK_COMPILER_VERBOSE=0, so the compiler chatter -- including the soft
  # "no .cmk extension" note -- is silenced.  Only the program's own output shows.
  (tmp_path / "hello.txt").write_text(HELLO)
  r = cmk("cmk", "run", "hello.txt", env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout
  assert "extension" not in r.stderr.lower()  # quiet on a successful run


def test_lint_warns_non_cmk_extension(cmk, tmp_path):
  # `cmk lint` (unlike `cmk run`) is verbose and DOES surface the extension note.
  (tmp_path / "hello.txt").write_text(HELLO)
  r = cmk("cmk", "lint", "hello.txt", env=SUP)
  assert r.ok, r.stderr
  assert "extension" in r.stderr.lower()


def test_lint_multiple_files(cmk, tmp_path):
  # `cmk lint` accepts several files; each is linted independently and reported.
  (tmp_path / "a.cmk").write_text(HELLO)
  (tmp_path / "b.cmk").write_text(HELLO)
  r = cmk("cmk", "lint", "a.cmk", "b.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "a.cmk" in r.stderr and "b.cmk" in r.stderr


def test_lint_multifile_continues_past_failure(cmk, tmp_path):
  # a bad file among good ones does not abort the run: the later file is still
  # linted, and the exit is nonzero because one failed.
  (tmp_path / "a.cmk").write_text(HELLO)
  (tmp_path / "b.cmk").write_text(HELLO)
  r = cmk("cmk", "lint", "a.cmk", "nope.cmk", "b.cmk", env=SUP)
  assert not r.ok
  assert "no such file" in r.stderr.lower()
  assert "b.cmk" in r.stderr  # loop continued past the missing file


# --- compile -----------------------------------------------------------------


def test_compile_to_file(cmk, tmp_path):
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "compile", "hello.cmk", "out.mk", env=SUP)
  assert r.ok, r.stderr
  out = tmp_path / "out.mk"
  assert out.exists()
  body = out.read_text()
  # full standalone (mk.compiler!): substantial, and self-contained, since it embeds
  # compose.mk and carries its own bash-polyglot shebang (a simple preview would
  # be a handful of lines with no shebang).
  assert len(body.splitlines()) > 1000
  assert body.lstrip().startswith("#!/usr/bin/env bash")
  # and it actually RUNS its __main__ (regression: mk.compiler! used to truncate
  # the embedded program via a path-broken sed -> flaky/non-runnable standalone).
  out.chmod(0o755)
  exe = subprocess.run(
    [str(out)],
    capture_output=True,
    text=True,
    cwd=str(tmp_path),
    env={**os.environ, "NO_COLOR": "1"},
  )
  assert "CMK-RUN-OK" in exe.stdout, exe.stderr


def test_compile_redirect_is_full(cmk, tmp_path):
  # captured stdout is not a tty -> full standalone on stdout (not the preview).
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "compile", "hello.cmk", env=SUP)
  assert r.ok, r.stderr
  assert len(r.stdout.splitlines()) > 1000
  assert r.stdout.lstrip().startswith("#!/usr/bin/env bash")


def test_compile_overwrite_warns(cmk, tmp_path):
  (tmp_path / "hello.cmk").write_text(HELLO)
  (tmp_path / "out.mk").write_text("preexisting\n")
  r = cmk("cmk", "compile", "hello.cmk", "out.mk", env=SUP)
  assert r.ok, r.stderr
  assert "overwriting" in r.stderr.lower()


# --- pipe-compile (bare `cmk` with source on stdin) --------------------------
# `echo 'hi: world' | ./compose.mk cmk` compiles the piped source -- the streaming
# peer of `cmk compile <file>` (the fixture always pipes stdin, so `[ -p ]` holds).
# A non-empty subcommand tail (`cmk run ..`, `cmk eval`, ..) still wins; only the
# bare, piped, tail-less form triggers the compile.


def test_pipe_compile_bare(cmk):
  # captured (non-tty) stdout -> the full standalone on stdout, exit 0.
  r = cmk("cmk", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("#!/usr/bin/env bash")
  assert len(r.stdout.splitlines()) > 1000
  # the dispatcher (usage / __main__) must not also run after the compile.
  assert "USAGE" not in r.stderr and "unknown subcommand" not in r.stderr


def test_pipe_compile_output_runs(cmk, tmp_path):
  # the piped-compile standalone is runnable, like `cmk compile <file>` output.
  r = cmk("cmk", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  out = tmp_path / "piped.mk"
  out.write_text(r.stdout)
  out.chmod(0o755)
  exe = subprocess.run(
    [str(out)],
    capture_output=True,
    text=True,
    cwd=str(tmp_path),
    env={**os.environ, "NO_COLOR": "1"},
  )
  assert "CMK-RUN-OK" in exe.stdout, exe.stderr


def test_pipe_does_not_hijack_subcommand(cmk, tmp_path):
  # source on stdin but an explicit subcommand tail -> dispatch, not pipe-compile.
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "run", "hello.cmk", stdin="ignored: stdin\n", env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout
  # it ran the file rather than emitting a compiled Makefile on stdout.
  assert not r.stdout.lstrip().startswith("#!/usr/bin/env bash")


def test_pipe_compile_alias_cli_cmk(cmk):
  # the canonical `cli.cmk` entrypoint honors the same pipe-compile shortcut.
  r = cmk("cli.cmk", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("#!/usr/bin/env bash")


def test_pipe_compile_explicit_subcommand(cmk):
  # an explicit `cmk compile` with source on stdin but NO file compiles the pipe --
  # same as bare `cmk`.  Regression: this used to route to the parametric handler
  # with an empty stem (`No rule to make target 'cli.cmk.compile/'`).
  r = cmk("cmk", "compile", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("#!/usr/bin/env bash")
  assert "No rule to make target" not in r.stderr


def test_compile_file_wins_over_stdin(cmk, tmp_path):
  # `cmk compile <file>` with source also on stdin compiles the file, not the pipe
  # (only a bare `compile` tail triggers the stdin shortcut).
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = cmk("cmk", "compile", "hello.cmk", stdin="STDIN_SENTINEL_TGT: x\n", env=SUP)
  assert r.ok, r.stderr
  # the compiled standalone carries the file's real recipe, not the stdin token.
  assert "CMK-RUN-OK" in r.stdout
  assert "STDIN_SENTINEL_TGT" not in r.stdout


def test_pipe_transpile_explicit_subcommand(cmk):
  # `cmk transpile` with source on stdin, no file -> the bare fragment (lang.transpile):
  # no shebang / payload wrapper, unlike `cmk compile`.  Same file-less shortcut path.
  r = cmk("cmk", "transpile", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  assert "echo CMK-RUN-OK" in r.stdout
  assert not r.stdout.lstrip().startswith("#!/usr/bin/env")
  assert "MAKEFILE_LIST+=" not in r.stdout
  assert "No rule to make target" not in r.stderr


def test_pipe_run_explicit_subcommand(cmk):
  # `cmk run` with source on stdin but NO file compiles + executes the pipe (routed via
  # the `-` stdin sentinel).  Regression: used to hit `No rule to make target
  # 'cli.cmk.run/'`.  Unlike compile/transpile it runs the program, not emit it.
  r = cmk("cmk", "run", stdin=HELLO, env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout
  assert not r.stdout.lstrip().startswith("#!/usr/bin/env bash")
  assert "No rule to make target" not in r.stderr


def test_pipe_run_surfaces_compile_error(cmk):
  # the point of `cmk run` on a pipe: a program that fails to lower surfaces its own
  # compile error (not a swallowed no-op).  A bare module-level banana is inert text
  # that make can't parse -> a `missing separator` at interpret time.
  r = cmk("cmk", "run", stdin="(|hello world|)\n", env=SUP)
  assert not r.ok
  assert "missing separator" in (r.stdout + r.stderr)


# --- doc ---------------------------------------------------------------------


def test_doc_adds_shebang_and_checks(cmk, tmp_path):
  f = tmp_path / "hello.cmk"
  f.write_text(HELLO)  # no shebang
  r = cmk("cmk", "doc", "hello.cmk", env=SUP)
  assert r.ok, r.stderr
  first = f.read_text().splitlines()[0]
  # mode-matching shebang routing back through `cmk run`.
  assert first.startswith("#!") and "cmk run" in first
  assert os.access(f, os.X_OK)  # chmod +x
  assert "compiles ok" in r.stderr.lower()  # compile-check passed


def test_doc_is_idempotent(cmk, tmp_path):
  f = tmp_path / "hello.cmk"
  f.write_text("#!/usr/bin/env -S ./compose.mk cmk run\n" + HELLO)
  r = cmk("cmk", "doc", "hello.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "already present" in r.stderr.lower()
  # unchanged: still exactly one shebang.
  assert f.read_text().count("#!/usr/bin/env") == 1


# --- build (needs docker: makeself) ------------------------------------------


@pytest.mark.needs_docker
def test_build_makes_runnable_binary(docker_cmk, tmp_path):
  (tmp_path / "hello.cmk").write_text(HELLO)
  r = docker_cmk(
    "cmk", "build", "hello.cmk", "hello.bin", env=SUP, timeout=600
  )
  assert r.ok, r.stderr
  binpath = tmp_path / "hello.bin"
  assert binpath.exists() and os.access(binpath, os.X_OK)
  # the produced binary self-extracts and runs the bundled CMK app.
  out = subprocess.run(
    [str(binpath)],
    capture_output=True,
    text=True,
    cwd=str(tmp_path),
    env={**os.environ, "CMK_SUPERVISOR": "1", "NO_COLOR": "1"},
  )
  assert "CMK-RUN-OK" in out.stdout, out.stderr


# --- file identity -----------------------------------------------------------


def test_file_identity_in_make_context_and_host_machine_block(cmk, tmp_path):
  """`cmk run <f>` binds the interpreted file's own path, visible two ways.

  In make context it expands at parse/recipe time; inside a host-machine block
  it arrives as plain process env.  The docker crossing is pinned below.
  """
  (tmp_path / "ident.cmk").write_text(
    "open cmk\nmachine hm(| entrypoint=bash |)\n"
    "$(info MF=[${__file__}])\n"
    'd:\n  (| echo "BF=[$__file__]" |) in hm\n'
    "__main__: d\n"
  )
  r = cmk("cmk", "run", "ident.cmk", env=SUP)
  out = r.stdout + r.stderr
  assert r.ok, out[-2000:]
  assert "MF=[ident.cmk]" in out, out[-2000:]
  assert "BF=[ident.cmk]" in out, out[-2000:]


@pytest.mark.needs_docker
def test_file_identity_crosses_the_container_boundary(docker_cmk, tmp_path):
  # rides the standard-env crossing, and the workspace mount keeps the relative path valid.
  (tmp_path / "file_box.cmk").write_text(
    "open cmk\n"
    "container boxy(img=alpine entrypoint=sh)(| |)\n"
    "foo:\n"
    '\t(| echo "BOX_FILE=[$__file__] BOX_CMK=[$__cmk__] BOX_INTERP=[$__interpreter__]" |) in boxy\n'
  )
  r = docker_cmk("cmk", "run", "file_box.cmk", "foo", timeout=300, env=SUP)
  out = r.stdout + r.stderr
  assert r.returncode == 0, out[-2000:]
  assert "BOX_FILE=[file_box.cmk]" in out, out[-2000:]
  # this-program identity: the compiled temp, workspace-relative so it stays valid in the box.
  assert "BOX_CMK=[./.tmp." in out, out[-2000:]
  # interpreter identity, rewritten by the crossing to the form valid where the block stands.
  line = next(l for l in out.splitlines() if "BOX_INTERP=" in l)
  assert "BOX_INTERP=[]" not in line, line
  assert "compose.mk]" in line, line


def test_program_reinvokes_itself_via_cmk_dunder(cmk, tmp_path):
  """A program's argv0 is exported as its own re-invokable handle.

  Inside an interpreted run that is the compiled artifact, so the re-exec
  skips the compile front door entirely (no second compile line appears).
  """
  (tmp_path / "quine.cmk").write_text(
    "leaf:\n\techo LEAF_RAN VIA=[$${__cmk__}]\n"
    "hop:\n\t$${__cmk__} leaf\n"
    "__main__: hop\n"
  )
  r = cmk("cmk", "run", "quine.cmk", env=SUP)
  out = r.stdout + r.stderr
  assert r.ok, out[-2000:]
  assert "LEAF_RAN" in out, out[-2000:]
  assert "VIA=[./.tmp." in out, out[-2000:]
