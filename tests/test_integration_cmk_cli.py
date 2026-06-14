"""Integration tests for the public `cmk` subcommand interface (compose.mk).

`cmk` is a convenience front-end uniting several internal CMK workflows:

  cmk build <f> [bin]   -> mk.pkg            (self-extracting binary)  [needs_docker]
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


# --- guards (cross-cutting file hygiene) -------------------------------------


def test_missing_input_fails(cmk):
  r = cmk("cmk", "run", "nope.cmk", env=SUP)
  assert not r.ok
  assert "no such file" in r.stderr.lower()


def test_warn_non_cmk_extension(cmk, tmp_path):
  # a non-.cmk input warns but still proceeds.
  (tmp_path / "hello.txt").write_text(HELLO)
  r = cmk("cmk", "run", "hello.txt", env=SUP)
  assert r.ok, r.stderr
  assert "CMK-RUN-OK" in r.stdout
  assert "extension" in r.stderr.lower()


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
  assert body.lstrip().startswith("#!/usr/bin/env -S bash")
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
  assert r.stdout.lstrip().startswith("#!/usr/bin/env -S bash")


def test_compile_overwrite_warns(cmk, tmp_path):
  (tmp_path / "hello.cmk").write_text(HELLO)
  (tmp_path / "out.mk").write_text("preexisting\n")
  r = cmk("cmk", "compile", "hello.cmk", "out.mk", env=SUP)
  assert r.ok, r.stderr
  assert "overwriting" in r.stderr.lower()


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
