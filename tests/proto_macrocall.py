"""PROTOTYPE tests for the `cmk.NAME[BODY]` callable-macro bracket syntax.

NOT named `test_*.py`, so excluded from default discovery (pytest.ini
`python_files`).  Run explicitly:

    pytest tests/proto_macrocall.py -q

The new `.awk.macrocall` stage (after `callable`, before `blockref`/`triplequote`)
lowers `cmk.NAME[BODY]` -> `BODY | $(call NAME)` -- the MACRO analog of the
callable-target form.  Happy paths assert the FULLY-compiled `mk.compile` output;
error cases use the standalone `mk.preprocess.macrocall` target so the nonzero exit
is observable (mirrors tests/test_compiler_cmk.py::test_callable_*).
"""

SQ = "'''"


def test_quoted_single_line(cmk):
  # demo5
  r = cmk("mk.compile", stdin=f"x:\n\tcmk.h[{SQ}1 2 3 4{SQ}]\n")
  assert r.ok, r.stderr
  assert "printf '%s' '1 2 3 4' | $(call h)" in r.stdout


def test_quoted_doublequote_interpolating(cmk):
  # demo8
  r = cmk("mk.compile", stdin='x:\n\tcmk.h["""${V}"""]\n')
  assert r.ok, r.stderr
  assert "printf '%s' \"${V}\" | $(call h)" in r.stdout


def test_quoted_multiline_bracket_on_own_line(cmk):
  # demo6: `]` on its own line after the closing ''' -> eat_to_bracket getlines to it.
  r = cmk("mk.compile", stdin=f"x:\n\tcmk.h[{SQ}L1\nL2{SQ}\n]\n")
  assert r.ok, r.stderr
  assert "printf '%s\\n%s' 'L1' 'L2' | $(call h)" in r.stdout


def test_unquoted_target_body(cmk):
  # demo7: this.X already lowered to ${make} X by dialect before this stage.
  r = cmk("mk.compile", stdin="x:\n\tcmk.h[this.t]\n")
  assert r.ok, r.stderr
  assert "${make} t | $(call h)" in r.stdout


def test_glyph_fd_gets_cat_prefix(cmk):
  # demo9: bare ⬦ref can't be a pipe LHS -> `cat ` prepended BEFORE blockref lowers it.
  r = cmk("mk.compile", stdin="x:\n\tcmk.h[⬦ref]\n")
  assert r.ok, r.stderr
  assert "cat <($(call mk.def_to_fd, ref)) | $(call h)" in r.stdout


def test_glyph_file_gets_cat_prefix(cmk):
  # demo10: filled diamond ⬥ -> real local file.
  r = cmk("mk.compile", stdin="x:\n\tcmk.h[⬥ref]\n")
  assert r.ok, r.stderr
  assert "cat $(call mk.def.tmpfile, ref) | $(call h)" in r.stdout


def test_unquoted_non_command_is_not_a_compile_error(cmk):
  # demo11: `1 2 3 4` lowers verbatim (runtime error, not compile error).
  r = cmk("mk.compile", stdin="x:\n\tcmk.h[1 2 3 4]\n")
  assert r.ok, r.stderr
  assert "1 2 3 4 | $(call h)" in r.stdout


def test_paren_form_left_untouched(cmk):
  # cmk.NAME(args) is the $(call NAME,args) form -- macrocall must not touch it
  # (main.preprocess lowers it later).
  r = cmk("mk.compile", stdin="x:\n\tcmk.h(a,b)\n")
  assert r.ok, r.stderr
  assert "$(call h,a,b)" in r.stdout


def test_inert_inside_define(cmk):
  r = cmk("mk.compile", stdin=f"define blk\ncmk.h[{SQ}x{SQ}]\nendef\n")
  assert r.ok, r.stderr
  assert f"cmk.h[{SQ}x{SQ}]" in r.stdout


def test_error_unterminated_unquoted(cmk):
  r = cmk("mk.preprocess.macrocall", stdin="x:\n\tcmk.h[a b\n")
  assert not r.ok
  assert "compose.mk (cmk:macrocall) error:" in r.stderr
  assert "unterminated" in r.stderr
  assert "at line" in r.stderr


def test_error_mixed_content(cmk):
  r = cmk("mk.preprocess.macrocall", stdin=f"x:\n\tcmk.h[{SQ}a{SQ} more]\n")
  assert not r.ok
  assert "expected ']'" in r.stderr


def test_error_unterminated_literal(cmk):
  r = cmk("mk.preprocess.macrocall", stdin=f"x:\n\tcmk.h[{SQ}oops\n")
  assert not r.ok
  assert "unterminated triple-quoted literal" in r.stderr


# --- combined call-with-args + bracket-stdin (demos 12/13) ------------------
# `(args)` is carried verbatim into a `cmk.NAME(args)` callform that mainpre then
# lowers to `$(call NAME,args)`; both arg-orders normalize to the same pipe form.


def test_with_args_paren_then_bracket(cmk):
  # demo12
  r = cmk(
    "mk.compile", stdin="x:\n\tcmk.macro_with_args(one,two)[THE LOG LANDED]\n"
  )
  assert r.ok, r.stderr
  assert "THE LOG LANDED | $(call macro_with_args,one,two)" in r.stdout


def test_with_args_bracket_then_paren(cmk):
  # demo13: swapped order -- must compile identically to demo12.
  r = cmk(
    "mk.compile", stdin="x:\n\tcmk.macro_with_args[THE LOG LANDED](one,two)\n"
  )
  assert r.ok, r.stderr
  assert "THE LOG LANDED | $(call macro_with_args,one,two)" in r.stdout


def test_args_may_contain_brackets(cmk):
  # (args) is balanced-paren scanned, so `[`/`]` inside it are ordinary chars.
  r = cmk("mk.compile", stdin="x:\n\tcmk.f(x[0],y)[B]\n")
  assert r.ok, r.stderr
  assert "B | $(call f,x[0],y)" in r.stdout
