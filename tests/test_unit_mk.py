"""Tests for the mk.* reflection / meta-programming targets.

These exercise compose.mk's introspection helpers (variable + define lookup,
namespace listing, env/tool assertions, makefile validation). They're pure and
no-docker. The CMK compiler/transpiler targets (mk.compile, mk.interpret,
mk.preprocess.*, and mk.parse golden output) are intentionally NOT covered here
— that's the deferred compiler test layer.

mk.* introspection partly reflects compose.mk on itself; where a test would
be brittle against the full target list, it asserts membership/shape rather
than an exact dump.
"""

import json
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _wrapper(tmp_path, body: str) -> Path:
  mk = tmp_path / "wrap.mk"
  mk.write_text(f"include {COMPOSE_MK}\n{body}\n")
  return mk


# --- variable / define lookup ----------------------------------------------


def test_mk_get_reads_variable(cmk):
  # env vars are imported as make variables, so this is deterministic.
  r = cmk("mk.get/MYVAR", env={"MYVAR": "hello42"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "hello42"


def test_mk_def_read(cmk, tmp_path):
  mk = _wrapper(tmp_path, "define greeting\nhello world\nendef")
  r = cmk("mk.def.read/greeting", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout == "hello world\n"


# --- namespace / var introspection -----------------------------------------


def test_mk_namespace_list(cmk):
  r = cmk("mk.namespace.list")
  assert r.ok, r.stderr
  namespaces = set(r.stdout.split())
  assert {"io", "stream", "docker", "flux", "mk"} <= namespaces


def test_mk_vars_filter(cmk):
  r = cmk("mk.vars.filter/OS_NAME")
  assert r.ok, r.stderr
  assert "OS_NAME" in r.stdout


# --- env / tool assertions -------------------------------------------------


def test_mk_assert_env_present(cmk):
  r = cmk("mk.assert.env/FOO", env={"FOO": "1"})
  assert r.ok, r.stderr


def test_mk_assert_env_missing_fails(cmk):
  r = cmk("mk.assert.env/DEFINITELY_UNSET_XYZ")
  assert not r.ok


def test_mk_require_tool_present(cmk):
  r = cmk("mk.require.tool/bash")
  assert r.ok, r.stderr


def test_mk_require_tool_missing_fails(cmk):
  r = cmk("mk.require.tool/nope-xyz123")
  assert not r.ok


def test_mk_ifdef(cmk):
  assert cmk("mk.ifdef/FOO", env={"FOO": "1"}).ok
  assert not cmk("mk.ifdef/DEFINITELY_UNSET_XYZ").ok


# --- makefile validation ---------------------------------------------------


def test_mk_validate_accepts_valid_stdin(cmk):
  r = cmk("mk.validate", stdin="foo:; @true\n")
  assert r.ok, r.stderr


def test_mk_validate_rejects_broken_file(cmk, tmp_path):
  bad = tmp_path / "bad.mk"
  bad.write_text("this is :::: not valid\n\tgarbage\n")
  r = cmk(f"mk.validate/{bad}")
  assert not r.ok


# --- status / vars / conditionals / filesystem -----------------------------


def test_mk_stat(cmk):
  r = cmk("mk.stat")
  assert r.ok, r.stderr
  assert json.loads(r.stdout).get("make_version")


def test_mk_vars(cmk):
  r = cmk("mk.vars")
  assert r.ok, r.stderr
  assert "ALPINE_VERSION" in r.stdout


def test_mk_ifndef(cmk):
  assert cmk("mk.ifndef/DEFINITELY_UNSET_XYZ").ok
  assert not cmk("mk.ifndef/FOO", env={"FOO": "1"}).ok


def test_mk_clean(cmk, tmp_path):
  (tmp_path / ".tmp.x").write_text("")
  r = cmk("mk.clean")
  assert r.ok, r.stderr
  assert not (tmp_path / ".tmp.x").exists()


def test_mk_require_dir(cmk, tmp_path):
  r = cmk("mk.require.dir/newdir")
  assert r.ok, r.stderr
  assert (tmp_path / "newdir").is_dir()


def test_mk_def_to_file(cmk, tmp_path):
  mk = _wrapper(tmp_path, "define greeting\nhello world\nendef")
  r = cmk("mk.def.to.file/greeting/out.txt", makefile=mk)
  assert r.ok, r.stderr
  assert (tmp_path / "out.txt").read_text().strip() == "hello world"


def test_mk_run(cmk, tmp_path):
  # Runs the given makefile's default target in an isolated shell.
  (tmp_path / "sub.mk").write_text("hello:; @echo HELLO-MK-RUN\n")
  r = cmk("mk.run/sub.mk")
  assert r.ok, r.stderr
  assert "HELLO-MK-RUN" in r.stdout


def test_mk_def_dispatch(cmk, tmp_path):
  # Runs an interpreter on a define-block (here sh runs the script). Also the
  # same-line alias polyglot.dispatch.
  mk = _wrapper(tmp_path, "define script\necho SCRIPT-RAN\nendef")
  r = cmk("mk.def.dispatch/sh,script", makefile=mk)
  assert r.ok, r.stderr
  assert "SCRIPT-RAN" in r.stdout
