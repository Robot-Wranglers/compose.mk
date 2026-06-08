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
import os
import shutil
import subprocess
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


# --- mk.import.def : defs= (multiple) + wildcards ---------------------------
# `defs="a b ..."` imports several define-blocks, each under its own name; a spec
# with `*`/`?` is a glob matching every define whose name fits.
_DEFS_SRC = (
  "define salute.a\nhello A\nendef\n"
  "define salute.b\nhello B\nendef\n"
  "define other.x\nnope\nendef"
)


def test_mk_import_def_defs_multiple(cmk, tmp_path):
  _, con = _import_pair(
    tmp_path,
    _DEFS_SRC,
    "$(call mk.import.def, file=SRCPATH defs='salute.a salute.b')",
  )
  a = cmk("mk.def.read/salute.a", makefile=con)
  b = cmk("mk.def.read/salute.b", makefile=con)
  assert a.ok, a.stderr
  assert b.ok, b.stderr
  assert a.stdout == "hello A\n"
  assert b.stdout == "hello B\n"


def test_mk_import_def_defs_wildcard(cmk, tmp_path):
  # the glob imports every matching define, and nothing else.
  _, con = _import_pair(
    tmp_path, _DEFS_SRC, "$(call mk.import.def, file=SRCPATH defs='salute.*')"
  )
  assert cmk("mk.def.read/salute.a", makefile=con).stdout == "hello A\n"
  assert cmk("mk.def.read/salute.b", makefile=con).stdout == "hello B\n"
  # other.x did not match the glob, so it was not imported (empty value).
  assert cmk("mk.def.read/other.x", makefile=con).stdout.strip() == ""


def test_mk_import_def_defs_no_match(cmk, tmp_path):
  # a glob that matches nothing is a hard error.
  _, con = _import_pair(
    tmp_path, _DEFS_SRC, "$(call mk.import.def, file=SRCPATH defs='zzz*')"
  )
  r = cmk("flux.ok", makefile=con)
  assert not r.ok
  assert "no def matching" in r.stderr


# --- mk.import.target : import whole target(s) from another file ------------
# Targets (unlike defines) are not introspectable via $(value), so the importer
# extracts them textually and $(eval)s each as its own rule. The source below
# covers the gotchas: a multi-line recipe, an escaped `$$`, a `%`-stem pattern
# target, and a target name containing a `.` (which the extractor must regex-
# escape). The recipes round-trip because $(file <) + $(eval) keep deferred
# recipe expansion (so `$$`/`$*` survive to run-time).
_TARGETS_SRC = (
  "greet:\n"
  "\t@printf 'hi %s\\n' world\n"
  "\n"
  "twice:\n"
  "\t@printf 'a\\n'\n"
  "\t@printf 'b\\n'\n"
  "\n"
  "shouty:\n"
  '\t@echo "home=$${HOME:-none}"\n'
  "\n"
  "echo/%:\n"
  "\t@printf 'stem=%s\\n' \"$*\"\n"
)


def test_mk_import_target_single(cmk, tmp_path):
  # a multi-line-recipe target is recreated and runs (joined recipe still works).
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call mk.import.target, file=SRCPATH target=twice)",
  )
  r = cmk("twice", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "a\nb\n"


def test_mk_import_target_preserves_double_dollar(cmk, tmp_path):
  # an escaped `$$` round-trips, so `${VAR}`-style shell refs survive.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call mk.import.target, file=SRCPATH target=shouty)",
  )
  r = cmk("shouty", makefile=con, env={"HOME": "/x/y"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "home=/x/y"


def test_mk_import_target_multiple(cmk, tmp_path):
  # `targets="a b"` imports several at once (space-separated, quoted).
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    '$(call mk.import.target, file=SRCPATH targets="greet twice")',
  )
  g = cmk("greet", makefile=con)
  t = cmk("twice", makefile=con)
  assert g.ok, g.stderr
  assert t.ok, t.stderr
  assert g.stdout == "hi world\n"
  assert t.stdout == "a\nb\n"


def test_mk_import_target_pattern(cmk, tmp_path):
  # a `%`-stem pattern target imports and matches; `$*` (the stem) survives.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call mk.import.target, file=SRCPATH target=echo/%)",
  )
  r = cmk("echo/world", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "stem=world\n"


def test_mk_import_target_missing_file(cmk, tmp_path):
  # a nonexistent file is a hard error.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call mk.import.target, file=/no/such/file.mk target=twice)",
  )
  r = cmk("twice", makefile=con)
  assert not r.ok
  assert "file not found" in r.stderr


def test_mk_import_target_missing_target(cmk, tmp_path):
  # a target absent from the source file is a hard error.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call mk.import.target, file=SRCPATH target=nonesuch)",
  )
  r = cmk("nonesuch", makefile=con)
  assert not r.ok
  assert "no target matching" in r.stderr


# a source with a common prefix, for glob specs (`*` any run, `?` one char).
_GLOB_SRC = "foo.a:\n\t@echo aa\n\nfoo.b:\n\t@echo bb\n\nbar:\n\t@echo cc\n"


def test_mk_import_target_wildcard(cmk, tmp_path):
  # `targets='foo.*'` imports every matching target (foo.a + foo.b), not `bar`.
  _, con = _import_pair(
    tmp_path,
    _GLOB_SRC,
    "$(call mk.import.target, file=SRCPATH targets='foo.*')",
  )
  a = cmk("foo.a", makefile=con)
  b = cmk("foo.b", makefile=con)
  assert a.ok and b.ok, (a.stderr, b.stderr)
  assert a.stdout == "aa\n"
  assert b.stdout == "bb\n"
  # `bar` did NOT match the glob, so it was not imported.
  assert not cmk("bar", makefile=con).ok


def test_mk_import_target_wildcard_no_match(cmk, tmp_path):
  # a glob that matches nothing is a hard error (like an absent exact name).
  _, con = _import_pair(
    tmp_path,
    _GLOB_SRC,
    "$(call mk.import.target, file=SRCPATH targets='zzz*')",
  )
  r = cmk("foo.a", makefile=con)
  assert not r.ok
  assert "no target matching" in r.stderr


def test_mk_import_target_never_overrides_local(cmk, tmp_path):
  # An import never clobbers a local target: a glob silently skips names the
  # destination already defines (local wins, no "overriding recipe" warning --
  # which would otherwise spam on every recursive ${make}), while still importing
  # the non-overlapping ones.
  _, con = _import_pair(
    tmp_path,
    _GLOB_SRC,
    "$(call mk.import.target, file=SRCPATH targets='foo.*')\nfoo.a:\n\t@echo LOCAL\n",
  )
  a = cmk("foo.a", makefile=con)
  b = cmk("foo.b", makefile=con)
  assert a.ok, a.stderr
  assert b.ok, b.stderr
  assert a.stdout == "LOCAL\n"  # local override wins (foo.a import skipped)
  assert b.stdout == "bb\n"  # foo.b had no local def -> still imported
  assert "overriding recipe" not in a.stderr


# --- mk.kernel / mk.kernel.each : run a target-stream as an instruction set --
# mk.kernel BATCHES the stream into one `make a b c` invocation; mk.kernel.each
# re-enters make PER line. The contrast (dedup + whitespace vs. repeat + intact)
# is the whole reason both exist, so the tests pin exactly that.


def test_mk_kernel_runs_instructions(cmk):
  assert cmk("mk.kernel", stdin="flux.ok").ok
  assert not cmk("mk.kernel", stdin="flux.fail").ok


def test_mk_kernel_runs_composed_instruction(cmk):
  # a single parametric/composed instruction (no whitespace) batches fine.
  assert cmk("mk.kernel", stdin="flux.and/flux.ok,flux.ok").ok


def test_mk_kernel_dedups_repeats(cmk, tmp_path):
  # batch form -> `make tick tick tick` -> make builds the goal once -> 1 run.
  mk = _wrapper(tmp_path, "tick:; @echo TICK")
  r = cmk("mk.kernel", stdin="tick\ntick\ntick", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.count("TICK") == 1


def test_mk_kernel_each_reruns_repeats(cmk, tmp_path):
  # iterative form -> a separate `make tick` per line -> repeats actually re-run.
  mk = _wrapper(tmp_path, "tick:; @echo TICK")
  r = cmk("mk.kernel.each", stdin="tick\ntick\ntick", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.count("TICK") == 3


def test_mk_kernel_each_preserves_line_args(cmk, tmp_path):
  # a line carrying an argument (with spaces) stays intact -- the whitespace-
  # collapsing batch kernel would split it into separate goals.
  mk = _wrapper(tmp_path, 'say/%:; @echo "GOT=$*"')
  r = cmk("mk.kernel.each", stdin="say/a b", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "GOT=a b"


def test_mk_kernel_each_skips_blank_lines(cmk, tmp_path):
  mk = _wrapper(tmp_path, "tick:; @echo TICK")
  r = cmk("mk.kernel.each", stdin="tick\n\ntick", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.count("TICK") == 2


def test_mk_kernel_each_fails_fast(cmk, tmp_path):
  # a failing instruction aborts the stream; later instructions don't run.
  mk = _wrapper(tmp_path, "tick:; @echo TICK")
  r = cmk("mk.kernel.each", stdin="tick\nflux.fail\ntick", makefile=mk)
  assert not r.ok
  assert r.stdout.count("TICK") == 1


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


# --- dispatch path rewrite (global-install / tux) --------------------------
# `makefile_list.dind` rewrites compose.mk's host `-f` path to its in-container
# mount location (/usr/local/bin/compose.mk) ONLY when compose.mk lives OUTSIDE
# the workspace (a global / on-PATH install); a vendored in-workspace copy is left
# untouched. This is what makes the tux subsystem -- which dispatches compose.mk's
# OWN targets standalone -- work under a global install. These are pure/no-docker:
# they only inspect the command compose.mk *would* run in the container.
_DIND_ENV = {
  "NO_COLOR": "1",
  "CMK_SUPERVISOR": "0",
  "CMK_INTERNAL": "1",
  "CMK_DISABLE_HOOKS": "1",
  "TERM": "dumb",
  "TRACE": "0",
  "GITHUB_ACTIONS": "false",
}


def _stage(dirpath) -> Path:
  """Copy compose.mk into dirpath and make it executable (returns the path)."""
  prog = Path(dirpath) / "compose.mk"
  shutil.copy(COMPOSE_MK, prog)
  prog.chmod(0o755)
  return prog


def _run_staged(prog, *args, cwd, **env):
  merged = {**os.environ, **_DIND_ENV, **env}
  return subprocess.run(
    [str(prog), *args],
    text=True,
    capture_output=True,
    cwd=str(cwd),
    env=merged,
  )


def test_makefile_list_dind_rewrites_under_global_install(tmp_path):
  # compose.mk staged OUTSIDE the workspace -> mount engaged -> -f rewritten to
  # the canonical in-container mount path.
  bindir = tmp_path / "bin"
  bindir.mkdir()
  ws = tmp_path / "ws"
  ws.mkdir()
  prog = _stage(bindir)
  r = _run_staged(
    prog, "mk.get/makefile_list.dind", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert r.returncode == 0, r.stderr
  assert r.stdout.strip() == "-f/usr/local/bin/compose.mk"
  # the un-rewritten list still points at the (un-mountable) host path
  r2 = _run_staged(
    prog, "mk.get/makefile_list", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert str(prog) in r2.stdout


def test_makefile_list_dind_noop_when_vendored(tmp_path):
  # compose.mk staged INSIDE the workspace -> mount empty -> list unchanged.
  ws = tmp_path / "ws"
  ws.mkdir()
  prog = _stage(ws)
  r = _run_staged(
    prog, "mk.get/docker.cmk.mount", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert r.returncode == 0, r.stderr
  assert r.stdout.strip() == ""  # mount not engaged for an in-workspace copy
  rd = _run_staged(
    prog, "mk.get/makefile_list.dind", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  rl = _run_staged(
    prog, "mk.get/makefile_list", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert rd.stdout.strip() == rl.stdout.strip()
  assert "/usr/local/bin/compose.mk" not in rd.stdout


def test_tux_panes_uses_mount_path_under_global_install(tmp_path):
  # The pane shell-commands run INSIDE the tux container; under a global install
  # they must reference the mount path, never the (unreachable) host path.
  bindir = tmp_path / "bin"
  bindir.mkdir()
  ws = tmp_path / "ws"
  ws.mkdir()
  prog = _stage(bindir)
  r = _run_staged(
    prog, ".tux.panes/flux.ok", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert r.returncode == 0, r.stderr
  assert "/usr/local/bin/compose.mk" in r.stdout
  assert (
    str(bindir) not in r.stdout
  )  # host path must not leak into the pane cmd


def test_tux_panes_vendored_uses_local_path(tmp_path):
  ws = tmp_path / "ws"
  ws.mkdir()
  prog = _stage(ws)
  r = _run_staged(
    prog, ".tux.panes/flux.ok", cwd=ws, DOCKER_HOST_WORKSPACE=str(ws)
  )
  assert r.returncode == 0, r.stderr
  assert str(prog) in r.stdout  # the in-workspace path, unrewritten
  assert "/usr/local/bin/compose.mk" not in r.stdout
