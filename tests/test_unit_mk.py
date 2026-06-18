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


def test_hook_rewrite_skips_cmk(cmk):
  # `cmk <sub> <file>` is a greedy CLI-consumer (its tail is a subcommand, not
  # make goals), so the whole goal-line passes through UNwrapped -- otherwise a
  # `flux.post/cmk` hook token would poison cmk's own `${MAKE_CLI#*cmk}` parse.
  line = "cmk run demos/cmk/example.cmk"
  r = cmk("io.awk/.awk.rewrite.targets.maybe", stdin=line)
  assert r.ok, r.stderr
  assert r.stdout.strip() == line


# --- cli.subcommands engine: robust tail capture (.awk.subcommands.tail) ------
# The capture awk recovers a dispatcher's CLI tail from a (possibly hook-decorated)
# MAKE_CLI: drop up to & incl. `mk.supervisor.enter/<pid>`, drop flux.pre/* flux.post/*,
# drop the leading namespace token. Unit-tested in isolation via the io.awk idiom
# (no supervisor needed) by feeding fake MAKE_CLI strings on stdin.

_ANCHOR = (
  "make -sS --warn-undefined-variables -f ./compose.mk mk.supervisor.enter/9"
)


def _tail(cmk, goals: str) -> str:
  r = cmk("io.awk/.awk.subcommands.tail", stdin=f"{_ANCHOR} {goals}")
  assert r.ok, r.stderr
  return r.stdout.strip()


def test_subcommands_tail_decorated(cmk):
  # hooks-on: every bare word is wrapped flux.pre/X X flux.post/X (incl. the
  # namespace, the subcommand, and dotted-but-slashless files like foo.cmk).
  goals = (
    "flux.pre/cmk cmk flux.post/cmk flux.pre/run run flux.post/run "
    "flux.pre/foo.cmk foo.cmk flux.post/foo.cmk"
  )
  assert _tail(cmk, goals) == "run foo.cmk"


def test_subcommands_tail_undecorated(cmk):
  # hooks-off (the test env) or a skip-listed namespace: no decoration.
  assert _tail(cmk, "cmk run foo.cmk") == "run foo.cmk"


def test_subcommands_tail_path_arg(cmk):
  # slash-bearing args are never decorated by the rewrite; pass through intact.
  assert _tail(cmk, "cmk run demos/cmk/x.cmk") == "run demos/cmk/x.cmk"


def test_subcommands_tail_empty(cmk):
  # namespace with no args -> empty tail (engine then prints usage).
  assert _tail(cmk, "cmk") == ""


# --- define-block SELECT (.awk.select.def) ---------------------------------
# `mk.select.def/<spec>` emits, from a makefile stream on stdin, only the
# `define <name>..endef` blocks whose name matches <spec> (a glob with `*`/`?`,
# else an exact name). A selected block's NESTED inner defines pass through
# verbatim (depth-tracked); non-matching blocks (and their nesting) are dropped.

_DEFS = (
  "define alpha\nA body\nendef\n"
  "define beta\ndefine nested\nN\nendef\nB body\nendef\n"
  "other:; echo hi\n"
)


def test_select_def_exact_with_nested(cmk):
  r = cmk("mk.select.def/beta", stdin=_DEFS)
  assert r.ok, r.stderr
  # whole beta block incl. its nested define; alpha + the `other:` rule dropped.
  assert r.stdout == "define beta\ndefine nested\nN\nendef\nB body\nendef\n"


def test_select_def_glob(cmk):
  r = cmk("mk.select.def/a*", stdin=_DEFS)
  assert r.ok, r.stderr
  assert r.stdout == "define alpha\nA body\nendef\n"


def test_select_def_no_match_is_empty(cmk):
  r = cmk("mk.select.def/zzz", stdin=_DEFS)
  assert r.ok, r.stderr
  assert r.stdout == ""


# --- cli.subcommands engine: routing ----------------------------------------
# cli.subcommands never yields, so it runs fine WITHOUT the supervisor: invoke it
# directly with the subcmd_* env a client's `cli.subcommands.enter` would set, over a
# wrapper with parametric (.t.echo/%, .t.run/%) and non-parametric (.t.ping) handlers
# echoing the stem (${*}) and $argv.

# Handlers under namespace `.t` (parametric .t.echo/%, .t.run/%; non-parametric
# .t.ping) plus one under a SECOND namespace `.u` (for the MRO tests).
_SUBCMD_WRAPPER = (
  '.t.echo/%:; @printf \'echo %s [%s]\\n\' "${*}" "$${argv:-}"\n'
  '.t.run/%:; @printf \'run %s [%s]\\n\' "${*}" "$${argv:-}"\n'
  ".t.ping:; @printf 'ping [%s]\\n' \"$${argv:-}\"\n"
  ".u.extra:; @printf 'extra [%s]\\n' \"$${argv:-}\"\n"
)


def _denv(tail, default="run", subs="echo run ping", ns=".t"):
  # subcmd_ns is the namespace MRO (space-separated); sep joins ns and sub, so a
  # handler is `<ns><sep><sub>`, here `.t` + `.` + `echo` = `.t.echo`.
  return {
    "subcmd_name": "t",
    "subcmd_ns": ns,
    "subcmd_sep": ".",
    "subcmd_subs": subs,
    "subcmd_default": default,
    "subcmd_tail": tail,
  }


def test_subcommands_routes_known_parametric_sub(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("echo hi a b"))
  assert r.ok, r.stderr
  # parametric sub -> .t.echo/<arg1>, remaining args in $argv.
  assert "echo hi [a b]" in r.stdout


def test_subcommands_routes_non_parametric_sub(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("ping a b"))
  assert r.ok, r.stderr
  # non-parametric sub -> .t.ping (no stem), ALL remaining args in $argv.
  assert "ping [a b]" in r.stdout


def test_subcommands_routes_bare_to_default(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("myfile x"))
  assert r.ok, r.stderr
  # unrecognized first word -> the PARAMETRIC default (`.t.run/%`): it becomes the
  # default's stem (the `cmk <file>` shorthand), the rest in $argv.
  assert "run myfile [x]" in r.stdout


def test_subcommands_unknown_errors_when_default_nonparametric(cmk, tmp_path):
  # An unrecognized first word errors when the default is NON-parametric (`.t.ping`),
  # instead of silently running it -- a non-parametric default has no positional to
  # consume the word, so it's treated as a typo'd subcommand.
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("zzz", default="ping"))
  assert not r.ok
  assert "unknown subcommand" in r.stderr.lower()


def test_subcommands_help_prints_usage(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  for tail in ("help", "", "-h", "--help"):
    r = cmk("cli.subcommands", makefile=w, env=_denv(tail))
    assert r.ok, r.stderr
    assert "usage" in r.stderr.lower()
    for sub in (
      "echo",
      "run",
      "ping",
    ):  # each subcommand listed (one per line)
      assert sub in r.stderr


def test_subcommands_usage_marks_parametric(cmk, tmp_path):
  # the multi-line usage annotates parametric subs (.t.echo/%, .t.run/%) with `<arg>`
  # and leaves non-parametric (.t.ping) unannotated.
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("help"))
  assert r.ok, r.stderr
  lines = r.stderr.splitlines()
  echo_line = next(line for line in lines if "echo" in line)
  ping_line = next(line for line in lines if "ping" in line)
  assert "<arg>" in echo_line  # parametric -> accepts an argument
  assert "<arg>" not in ping_line  # non-parametric -> no argument


def test_subcommands_usage_terminates_last_item(cmk, tmp_path):
  # the tree uses ├ for items and ╰ (terminator) for the LAST subcommand (ping).
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("help"))
  assert r.ok, r.stderr
  lines = r.stderr.splitlines()
  echo_line = next(line for line in lines if "echo" in line)
  ping_line = next(line for line in lines if "ping" in line)  # last sub
  assert "├" in echo_line and "╰" not in echo_line
  assert "╰" in ping_line and "├" not in ping_line


def test_subcommands_no_handlers_errors(cmk, tmp_path):
  # With auto-detect, an omitted default falls back to the first reflected sub --
  # so the only "unknown subcommand" case is a namespace with NO handlers at all
  # (subs reflect empty -> default empty -> error).
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk(
    "cli.subcommands",
    makefile=w,
    env=_denv("whatever", default="", subs="", ns=".nope"),
  )
  assert not r.ok
  assert "unknown subcommand" in r.stderr.lower()


# --- cli.subcommands engine: namespace MRO ----------------------------------
# subcmd_ns may be a space-separated list, searched in order; the first namespace
# that defines a handler for the sub wins. `.u.extra` lives ONLY in the 2nd namespace.


def test_subcommands_mro_searches_second_namespace(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk(
    "cli.subcommands",
    makefile=w,
    env=_denv("extra a b", subs="echo extra", ns=".t .u"),
  )
  assert r.ok, r.stderr
  assert "extra [a b]" in r.stdout  # resolved from .u (not in .t)


def test_subcommands_mro_reflects_union(cmk, tmp_path):
  # empty subs -> reflect the union across BOTH namespaces in the MRO.
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk(
    "cli.subcommands",
    makefile=w,
    env=_denv("help", default="", subs="", ns=".t .u"),
  )
  assert r.ok, r.stderr
  for sub in ("echo", "run", "ping", "extra"):
    assert sub in r.stderr


# --- cli.subcommands engine: reflection (auto-detect subs + default) ---------
# When subcmd_subs is empty, the engine reflects the `.<ns>.<sub>` handlers (both
# parametric `/%` and non-parametric) from MAKEFILE_LIST (source order); when
# subcmd_default is empty, it uses the first reflected sub. The wrapper declares
# .t.echo/%, .t.run/%, then .t.ping (in that order).


def test_subcommands_reflects_subcommands(cmk, tmp_path):
  # subcmd_subs empty -> reflected (incl. the non-parametric .t.ping); ping routes.
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("ping a", subs=""))
  assert r.ok, r.stderr
  assert "ping [a]" in r.stdout


def test_subcommands_reflects_default_as_first_sub(cmk, tmp_path):
  # both empty -> subs reflected (echo run ping), default = first reflected sub
  # (echo); a bare arg routes to that default.
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk(
    "cli.subcommands", makefile=w, env=_denv("myfile x", default="", subs="")
  )
  assert r.ok, r.stderr
  assert "echo myfile [x]" in r.stdout


def test_subcommands_usage_lists_reflected_subs(cmk, tmp_path):
  w = _wrapper(tmp_path, _SUBCMD_WRAPPER)
  r = cmk("cli.subcommands", makefile=w, env=_denv("help", default="", subs=""))
  assert r.ok, r.stderr
  for sub in ("echo", "run", "ping"):  # reflected subcommands shown in usage
    assert sub in r.stderr


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


# --- import.def : import a define-block from another file ----------------
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
    tmp_path, _AWK_BLOCK, "$(call import.def, file=SRCPATH def=greet.awk)"
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
    "$(call import.def, file=SRCPATH def=greet.awk)\n"
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
    "$(call import.def, file=SRCPATH def=greet.awk as=greet.local)",
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
    "$(call import.def, file=SRCPATH def=shouty)\ngo:; @${shouty}",
  )
  r = cmk("go", makefile=con, env={"HOME": "/x/y"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "home=/x/y"


def test_mk_include_def_positional_shim(cmk, tmp_path):
  # the back-compat positional form: `include.def, <name>, <file>`.
  _, con = _import_pair(
    tmp_path,
    _AWK_BLOCK,
    "$(call include.def, greet.awk, SRCPATH)\n"
    "use:; @printf 'X\\n' | ${io.awk}/greet.awk",
  )
  r = cmk("use", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "hi X\n"


# --- import.def : defs= (multiple) + wildcards ---------------------------
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
    "$(call import.def, file=SRCPATH defs='salute.a salute.b')",
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
    tmp_path, _DEFS_SRC, "$(call import.def, file=SRCPATH defs='salute.*')"
  )
  assert cmk("mk.def.read/salute.a", makefile=con).stdout == "hello A\n"
  assert cmk("mk.def.read/salute.b", makefile=con).stdout == "hello B\n"
  # other.x did not match the glob, so it was not imported (empty value).
  assert cmk("mk.def.read/other.x", makefile=con).stdout.strip() == ""


def test_mk_import_def_defs_no_match(cmk, tmp_path):
  # a glob that matches nothing is a hard error.
  _, con = _import_pair(
    tmp_path, _DEFS_SRC, "$(call import.def, file=SRCPATH defs='zzz*')"
  )
  r = cmk("flux.ok", makefile=con)
  assert not r.ok
  assert "no def matching" in r.stderr


def test_mk_import_def_namespace(cmk, tmp_path):
  # namespace=<ns> prefixes the top-level bind name (<ns>.<name>) across the
  # selected set; the bare name is NOT defined.
  _, con = _import_pair(
    tmp_path,
    _DEFS_SRC,
    "$(call import.def, file=SRCPATH defs='salute.*' namespace=myns)",
  )
  assert cmk("mk.def.read/myns.salute.a", makefile=con).stdout == "hello A\n"
  assert cmk("mk.def.read/myns.salute.b", makefile=con).stdout == "hello B\n"
  assert (
    cmk("mk.def.read/salute.a", makefile=con).stdout.strip() == ""
  )  # bare absent


def test_mk_import_def_namespace_nested_verbatim(cmk, tmp_path):
  # only the TOP-LEVEL define header is renamed; a nested define stays verbatim.
  src_body = "define outer\nx:=1\ndefine inner\ny:=2\nendef\nendef"
  _, con = _import_pair(
    tmp_path,
    src_body,
    "$(call import.def, file=SRCPATH def=outer namespace=ns)",
  )
  body = cmk("mk.def.read/ns.outer", makefile=con).stdout
  assert "define inner" in body  # nested header untouched
  assert "ns.inner" not in body


# --- import.target : import whole target(s) from another file ------------
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
    "$(call import.target, file=SRCPATH target=twice)",
  )
  r = cmk("twice", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "a\nb\n"


def test_mk_import_target_preserves_double_dollar(cmk, tmp_path):
  # an escaped `$$` round-trips, so `${VAR}`-style shell refs survive.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call import.target, file=SRCPATH target=shouty)",
  )
  r = cmk("shouty", makefile=con, env={"HOME": "/x/y"})
  assert r.ok, r.stderr
  assert r.stdout.strip() == "home=/x/y"


def test_mk_import_target_multiple(cmk, tmp_path):
  # `targets="a b"` imports several at once (space-separated, quoted).
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    '$(call import.target, file=SRCPATH targets="greet twice")',
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
    "$(call import.target, file=SRCPATH target=echo/%)",
  )
  r = cmk("echo/world", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout == "stem=world\n"


def test_mk_import_target_missing_file(cmk, tmp_path):
  # a nonexistent file is a hard error.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call import.target, file=/no/such/file.mk target=twice)",
  )
  r = cmk("twice", makefile=con)
  assert not r.ok
  assert "file not found" in r.stderr


def test_mk_import_target_missing_target(cmk, tmp_path):
  # a target absent from the source file is a hard error.
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call import.target, file=SRCPATH target=nonesuch)",
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
    "$(call import.target, file=SRCPATH targets='foo.*')",
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
    "$(call import.target, file=SRCPATH targets='zzz*')",
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
    "$(call import.target, file=SRCPATH targets='foo.*')\nfoo.a:\n\t@echo LOCAL\n",
  )
  a = cmk("foo.a", makefile=con)
  b = cmk("foo.b", makefile=con)
  assert a.ok, a.stderr
  assert b.ok, b.stderr
  assert a.stdout == "LOCAL\n"  # local override wins (foo.a import skipped)
  assert b.stdout == "bb\n"  # foo.b had no local def -> still imported
  assert "overriding recipe" not in a.stderr


def test_mk_import_target_namespace(cmk, tmp_path):
  # namespace=<ns> renames each imported target <ns>.<name>, so it runs under the
  # prefix AND bypasses the never-override-local skip (a namespaced name can't
  # collide -- here a LOCAL `greet` exists, yet the import still lands as ns.greet).
  _, con = _import_pair(
    tmp_path,
    _TARGETS_SRC,
    "$(call import.target, file=SRCPATH target=greet namespace=myns)\n"
    "greet:; @echo local-greet\n",
  )
  r = cmk("myns.greet", makefile=con)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "hi world"  # the imported recipe, namespaced
  assert (
    cmk("greet", makefile=con).stdout.strip() == "local-greet"
  )  # local intact


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
  r = cmk("assert.env/FOO", env={"FOO": "1"})
  assert r.ok, r.stderr


def test_mk_assert_env_missing_fails(cmk):
  r = cmk("assert.env/DEFINITELY_UNSET_XYZ")
  assert not r.ok


def test_mk_require_tool_present(cmk):
  r = cmk("assert.tool.required/bash")
  assert r.ok, r.stderr


def test_mk_require_tool_missing_fails(cmk):
  r = cmk("assert.tool.required/nope-xyz123")
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
  r = cmk("mk.def.to.file/greeting,out.txt", makefile=mk)
  assert r.ok, r.stderr
  assert (tmp_path / "out.txt").read_text().strip() == "hello world"


def test_mk_def_to_file_default_name(cmk, tmp_path):
  # one positional arg: the def name doubles as the output filename.
  mk = _wrapper(tmp_path, "define greeting\nhello world\nendef")
  r = cmk("mk.def.to.file/greeting", makefile=mk)
  assert r.ok, r.stderr
  assert (tmp_path / "greeting").read_text().strip() == "hello world"


def test_mk_def_value_printf_preserves_specials(cmk, tmp_path):
  # 2nd arg -> single-line, recipe-safe `printf` of the block; $, parens and
  # quotes must survive both make and the shell intact.
  body = "define prog\nreduce inputs as $x (0; . + $x)\nendef\n"
  mk = _wrapper(tmp_path, body + "emit:; @$(call _mk.def.value, prog, _)\n")
  r = cmk("emit", makefile=mk)
  assert r.ok, r.stderr
  assert "reduce inputs as $x (0; . + $x)" in r.stdout


def test_mk_def_value_printf_multiline(cmk, tmp_path):
  # newlines in the block become a real newline in the emitted output (one
  # printf line, so make never splits the recipe).
  body = "define prog\nline one\nline two\nendef\n"
  mk = _wrapper(tmp_path, body + "emit:; @$(call _mk.def.value, prog, _)\n")
  r = cmk("emit", makefile=mk)
  assert r.ok, r.stderr
  assert "line one\nline two" in r.stdout


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
