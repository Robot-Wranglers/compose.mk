"""Tests for the mk.* reflection / meta-programming targets.

These exercise compose.mk's introspection helpers (variable + define lookup,
namespace listing, env/tool assertions, makefile validation). They're pure and
no-docker. The CMK compiler/transpiler targets (mk.compile, mk.interpret,
mk.preprocess.*, and mk.parse golden output) are intentionally NOT covered here
- that's the deferred compiler test layer.

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


# --- hook-rewrite skip-list (.awk.rewrite.targets.maybe) --------------------
# The supervisor wrapper rewrites each CLI goal `X` -> `flux.pre/X X flux.post/X`
# to inject pre/post hooks. Internal machinery (the interpreter + the compiler)
# is excluded from that rewrite -- hooking the compiler isn't a use-case, and
# the rewrite's per-goal `-q` existence checks are pure overhead there. These pin
# that skip-list (pure stdin->stdout awk; no wrapper/docker needed).


def test_hook_rewrite_wraps_normal_target(cmk):
  r = cmk("io.awk/.awk.rewrite.targets.maybe", stdin="build")
  assert r.ok, r.stderr
  assert r.stdout.strip() == "flux.pre/build build flux.post/build"


def test_hook_rewrite_skips_compiler_and_interpreter(cmk):
  # mk.compile / mk.preprocess / mk.interpret pass through UNwrapped (no hooks).
  for target in ("mk.compile", "mk.preprocess", "mk.interpret"):
    r = cmk("io.awk/.awk.rewrite.targets.maybe", stdin=target)
    assert r.ok, r.stderr
    assert r.stdout.strip() == target, f"{target} should not be hook-wrapped"


# --- `makefile_list` invariant (the -f args derived from MAKE_CLI) ----------
# `makefile_list` backs the `${make}` recursion macro; it must reflect the `-f`
# files of the *current* invocation. These pin the value in both invocation
# modes so the recursion machinery stays correct.


def test_makefile_list_standalone(cmk):
  # Tool mode (`./compose.mk ...`): the -f file is compose.mk itself.
  r = cmk("mk.get/makefile_list")
  assert r.ok, r.stderr
  assert "-f" in r.stdout and "compose.mk" in r.stdout


def test_makefile_list_library(cmk, tmp_path):
  # Library mode (`make -f wrap.mk`, which `include`s compose.mk): the -f file is
  # the user makefile (compose.mk is included, not on the CLI), so `${make}`
  # recurses into the user's makefile.
  mk = _wrapper(tmp_path, "noop:; @true")
  r = cmk("mk.get/makefile_list", makefile=mk)
  assert r.ok, r.stderr
  assert "-f" in r.stdout and "wrap.mk" in r.stdout


def test_mk_def_read(cmk, tmp_path):
  mk = _wrapper(tmp_path, "define greeting\nhello world\nendef")
  r = cmk("mk.def.read/greeting", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout == "hello world\n"


# --- mk.import.def : import a define-block from another file ----------------
# A source block with the gotchas that broke the old mk.get-based importer: an
# awk `$0`, an indented body, a blank line, and embedded double-quotes. These
# round-trip only because the importer reads via mk.def.read ($(value), which
# preserves `$`) and re-establishes the block inside a `define` wrapper.
_AWK_BLOCK = 'define greet.awk\n{\n  print "hi " $0\n\n  x = 1 + 2\n}\nendef'


def _import_pair(tmp_path, source_body, consumer_body):
  """Write a source file (with a define-block) and a consumer file that imports
  from it; `SRCPATH` in the consumer body is replaced with the source path."""
  src = tmp_path / "src.mk"
  src.write_text(f"include {COMPOSE_MK}\n{source_body}\n")
  con = tmp_path / "consumer.mk"
  con.write_text(
    f"include {COMPOSE_MK}\n{consumer_body.replace('SRCPATH', str(src))}\n"
  )
  return src, con


def test_mk_import_def_fidelity(cmk, tmp_path):
  # the imported block is byte-identical to the source's own definition.
  src, con = _import_pair(
    tmp_path, _AWK_BLOCK, "$(call mk.import.def, file=SRCPATH def=greet.awk)"
  )
  want = cmk("mk.def.read/greet.awk", makefile=src)
  got = cmk("mk.def.read/greet.awk", makefile=con)
  assert got.ok, got.stderr
  assert got.stdout == want.stdout
  assert (
    "$0" in got.stdout
  )  # the dollar survived (the old mk.get-based one ate it)


def test_mk_import_def_usable_via_io_awk(cmk, tmp_path):
  # the imported awk block actually runs as awk against stdin.
  _, con = _import_pair(
    tmp_path,
    _AWK_BLOCK,
    "$(call mk.import.def, file=SRCPATH def=greet.awk)\n"
    "use:; @printf 'world\\nthere\\n' | ${io.awk}/greet.awk",
  )
  r = cmk("use", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "hi world\nhi there\n"


def test_mk_import_def_as_rename(cmk, tmp_path):
  # `as=` imports the block under a different local name.
  src, con = _import_pair(
    tmp_path,
    _AWK_BLOCK,
    "$(call mk.import.def, file=SRCPATH def=greet.awk as=greet.local)",
  )
  want = cmk("mk.def.read/greet.awk", makefile=src)
  got = cmk("mk.def.read/greet.local", makefile=con)
  assert got.ok, got.stderr
  assert got.stdout == want.stdout


def test_mk_import_def_preserves_double_dollar(cmk, tmp_path):
  # a shell block's escaped `$$` round-trips, so `${VAR}`-style refs survive.
  _, con = _import_pair(
    tmp_path,
    'define shouty\necho "home=$${HOME:-none}"\nendef',
    "$(call mk.import.def, file=SRCPATH def=shouty)\ngo:; @${shouty}",
  )
  r = cmk("go", makefile=con, env={"HOME": "/x/y"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "home=/x/y"


def test_mk_include_def_positional_shim(cmk, tmp_path):
  # the back-compat positional form: `mk.include.def, <name>, <file>`.
  _, con = _import_pair(
    tmp_path,
    _AWK_BLOCK,
    "$(call mk.include.def, greet.awk, SRCPATH)\n"
    "use:; @printf 'X\\n' | ${io.awk}/greet.awk",
  )
  r = cmk("use", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "hi X\n"


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
