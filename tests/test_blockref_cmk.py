"""Tests for the `⬦`/`⬥` block-reference glyph constructs.

The two glyphs lower (in the `.awk.blockref` compile stage, after `callform`) to a materialization
of the operand:
    ⬦NAME  ->  <($(call _mk.def.to.fd, NAME))   (stream FD; hollow = transient)
    ⬥NAME  ->  $(call _mk.def.tmpfile, NAME)     (real local file; filled = on disk)
A plain-name operand is taken as-is (above).  A SELF-TOKEN operand (`⬦${self}`) is an OBJECT: it is
dispatched through its `__blockref__` dunder (its declared materializable representation) -- see
test_blockref_self_token_cmk.py -- so a fragment resolves to its shape without the caller naming it.

Stage-level golden lowering and full `mk.compile` cases stay compile-only; the
end-to-end cases compile AND run a tiny `.cmk` (locally, no docker) to prove the
FD/file actually feeds a command.
"""

import pytest

pytestmark = pytest.mark.compiler

SUP = {"CMK_SUPERVISOR": "1"}


def _fd(name):
  return "<($(call _mk.def.to.fd, " + name + "))"


def _file(name):
  return "$(call _mk.def.tmpfile, " + name + ")"


# --- stage-level golden lowering (lang.comp.pipeline.blockref) -------------------


def test_stage_stream_glyph(cmk):
  r = cmk("lang.comp.pipeline.blockref", stdin="x:; jq -f ⬦prog.jq\n")
  assert r.ok, r.stderr
  assert "jq -f " + _fd("prog.jq") in r.stdout


def test_stage_file_glyph(cmk):
  r = cmk("lang.comp.pipeline.blockref", stdin="y:; lean ⬥thm.lean\n")
  assert r.ok, r.stderr
  assert "lean " + _file("thm.lean") in r.stdout


def test_stage_multiple_glyphs_one_line(cmk):
  r = cmk("lang.comp.pipeline.blockref", stdin="z:; run ⬦a then ⬥b end\n")
  assert r.ok, r.stderr
  assert "run " + _fd("a") + " then " + _file("b") + " end" in r.stdout


def test_stage_bare_glyph_passes_through(cmk):
  # a glyph not followed by a NAME char is left verbatim.
  r = cmk("lang.comp.pipeline.blockref", stdin="z:; echo ⬦ bare\n")
  assert r.ok, r.stderr
  assert "echo ⬦ bare" in r.stdout


def test_stage_inert_inside_define(cmk):
  # blocks are literal: a glyph inside define..endef must NOT be lowered.
  src = "define d\ninside ⬦keepme literal\nendef\n"
  r = cmk("lang.comp.pipeline.blockref", stdin=src)
  assert r.ok, r.stderr
  assert "inside ⬦keepme literal" in r.stdout
  assert "_mk.def.to.fd" not in r.stdout


# --- full pipeline (mk.compile) --------------------------------------------


def test_compile_lowers_glyph_in_recipe(ir):
  src = "define prog\n. + 1\nendef\nt:; jq -f ⬦prog\n"
  r = ir(src)
  assert "jq -f " + _fd("prog") in r.stdout


# --- end-to-end (cmk run): the FD actually feeds a command -------------------


def test_e2e_stream_feeds_jq(cmk, tmp_path):
  prog = "define prog.jq\nreduce inputs as $x (0; . + $x)\nendef\n"
  main = "__main__:; '''1 2 3 4''' | jq -n -f ⬦prog.jq\n"
  (tmp_path / "p.cmk").write_text(prog + main)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "10" in r.stdout.split()


def test_e2e_stream_feeds_awk(cmk, tmp_path):
  prog = "define up.awk\n{ print toupper($0) }\nendef\n"
  main = "__main__:; echo hello | awk -f ⬦up.awk\n"
  (tmp_path / "p.cmk").write_text(prog + main)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "HELLO" in r.stdout


def test_e2e_file_glyph_yields_real_path(cmk, tmp_path):
  # ⬥ materializes a real file; `wc -c` on it proves a seekable path exists.
  prog = "define blk\nabcde\nendef\n"
  main = "__main__:; cat ⬥blk\n"
  (tmp_path / "p.cmk").write_text(prog + main)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "abcde" in r.stdout


def test_e2e_file_glyph_tmpfile_swept_at_end_of_run(cmk, tmp_path):
  # ⬥ tmpfiles are run-id-scoped (.tmp.cmk.brf.*) and the supervisor teardown
  # sweeps them, so nothing is left behind in the cwd after the run.
  prog = "define blk\nabcde\nendef\n"
  main = "__main__:; wc -c ⬥blk\n"
  (tmp_path / "p.cmk").write_text(prog + main)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  leftover = list(tmp_path.glob(".tmp.cmk.brf.*"))
  assert not leftover, f"brf tmpfiles not cleaned up: {leftover}"


# --- fidelity: backslash/quote-heavy block survives the round-trip ----------


def test_e2e_backslash_fidelity(cmk, tmp_path):
  # an awk program full of backslashes/regex must reach awk intact via ⬦.
  prog = (
    'define bs.awk\n{ gsub(/\\t/, "_"); gsub(/\\./, "-"); print }\nendef\n'
  )
  main = "__main__:; printf 'a\\tb.c\\n' | awk -f ⬦bs.awk\n"
  (tmp_path / "p.cmk").write_text(prog + main)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "a_b-c" in r.stdout


# --- constructor-form blockref: `blockref NAME(| .. |)` -----------------------
# The KIND dual of the glyphs: a Materializable kind (the same materialization surface a dsl
# kind carries), so it stamps `.fd`/`.file`/`.shape` on the captured block.  A module-level
# block -- which the recipe-line glyph stage cannot reach -- is still materializable on demand,
# through the same materialization seams the glyphs use.


def test_kind_lowers_to_ctor_call(ir):
  r = ir("blockref g(|\nhi\n|)\nx:; @true\n")
  assert "$(call blockref, def=g)" in r.stdout


def test_kind_fd_feeds_command(cmk, tmp_path):
  # `${NAME.fd}` is a `<(..)` process-sub FD of the captured block.
  src = "blockref g(|\nhello block\n|)\n__main__:; cat $(g.fd)\n"
  (tmp_path / "p.cmk").write_text(src)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "hello block" in r.stdout


def test_kind_file_yields_real_path(cmk, tmp_path):
  # `${NAME.file}` routes through `_mk.def.tmpfile` -> a readable on-disk path.
  src = "blockref g(|\nabcde\n|)\n__main__:; cat $(g.file)\n"
  (tmp_path / "p.cmk").write_text(src)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "abcde" in r.stdout


def test_kind_fd_feeds_awk(cmk, tmp_path):
  # a raw awk block captured as a KIND, fed to `awk -f` via its `.fd`.
  src = "blockref up.awk(|\n{ print toupper($0) }\n|)\n__main__:; echo hi | awk -f $(up.awk.fd)\n"
  (tmp_path / "p.cmk").write_text(src)
  r = cmk("cmk", "run", "p.cmk", env=SUP)
  assert r.ok, r.stderr
  assert "HI" in r.stdout
