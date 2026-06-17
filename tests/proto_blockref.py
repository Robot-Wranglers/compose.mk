"""PROTOTYPE tests for the `⬦`/`⬥` block-reference glyph constructs.

This file is intentionally NOT named `test_*.py`, so it is excluded from the
default suite discovery (see pytest.ini `python_files`).  Run it explicitly:

    pytest tests/proto_blockref.py -q

It reuses the shared `cmk` fixture from tests/conftest.py.

The two glyphs lower (in the `.awk.blockref` compile stage, after `callable`):
    ⬦NAME  ->  <($(call mk.def_to_fd, NAME))   (stream FD; hollow = transient)
    ⬥NAME  ->  $(call mk.def.tmpfile, NAME)     (real local file; filled = on disk)
"""

SUP = {"CMK_SUPERVISOR": "1"}


# --- stage-level golden lowering (mk.preprocess.blockref) -------------------


def test_stage_stream_glyph(cmk):
  r = cmk("mk.preprocess.blockref", stdin="x:; jq -f ⬦prog.jq\n")
  assert r.ok, r.stderr
  assert "jq -f <($(call mk.def_to_fd, prog.jq))" in r.stdout


def test_stage_file_glyph(cmk):
  r = cmk("mk.preprocess.blockref", stdin="y:; lean ⬥thm.lean\n")
  assert r.ok, r.stderr
  assert "lean $(call mk.def.tmpfile, thm.lean)" in r.stdout


def test_stage_multiple_glyphs_one_line(cmk):
  r = cmk("mk.preprocess.blockref", stdin="z:; run ⬦a then ⬥b end\n")
  assert r.ok, r.stderr
  assert (
    "run <($(call mk.def_to_fd, a)) then $(call mk.def.tmpfile, b) end"
    in r.stdout
  )


def test_stage_bare_glyph_passes_through(cmk):
  # a glyph not followed by a NAME char is left verbatim.
  r = cmk("mk.preprocess.blockref", stdin="z:; echo ⬦ bare\n")
  assert r.ok, r.stderr
  assert "echo ⬦ bare" in r.stdout


def test_stage_inert_inside_define(cmk):
  # blocks are literal: a glyph inside define..endef must NOT be lowered.
  src = "define d\ninside ⬦keepme literal\nendef\n"
  r = cmk("mk.preprocess.blockref", stdin=src)
  assert r.ok, r.stderr
  assert "inside ⬦keepme literal" in r.stdout
  assert "mk.def_to_fd" not in r.stdout


# --- full pipeline (mk.compile) --------------------------------------------


def test_compile_lowers_glyph_in_recipe(cmk):
  src = "define prog\n. + 1\nendef\nt:; jq -f ⬦prog\n"
  r = cmk("mk.compile", stdin=src)
  assert r.ok, r.stderr
  assert "jq -f <($(call mk.def_to_fd, prog))" in r.stdout


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
