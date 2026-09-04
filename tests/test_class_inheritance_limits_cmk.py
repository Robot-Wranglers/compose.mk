"""How a cmk `class`/`bases=` kind inherits and overrides members.

The class engine gives correct linear-MRO resolution: a kind stamps each mixin's
members onto the instance in `.__mixins` order (base-first, own-body last), so a
more-derived member overrides a base one.  `.__mro__` is a separate, `$(sort)`ed
SET used only by `issubclass`/`isinstance` membership tests, not by
resolution -- so the sort is correct there and never decides an override.

Override cleanliness depends on what a member lowers to.  A macro (`${self}.x = ..`)
overrides by plain variable reassignment: silent, last (most derived) wins.  A
recipe TARGET (`${self}.x:` with recipe lines) used to hand make a SECOND recipe
for the same target -- derived still won, but make warned ("overriding recipe for
target"), so a kind that leaned on it could not be warning-clean.

That limitation is now FIXED at the engine: `lang.class.shadowclean` (in `lang.class`)
rewrites a mixin chain so a base mixin's recipe target is physically stripped from
a cloned body when a more-derived mixin redefines it -- make sees exactly one
recipe, the derived one, with no warning.  The extraction (`.awk.self.targets`)
and removal (`.awk.self.strip`) run once per class at parse; the per-instance path
stays pure make.  Only actually-overridden targets are stripped; a non-overridden
base target is inherited untouched.

Both override paths (macro and recipe target) are guarded below.
"""

import pytest

pytestmark = pytest.mark.compiler


def run_cmk(cmk, tmp_path, src):
  """Write `src` to a temp .cmk and run it through real `cmk run` dispatch."""
  f = tmp_path / "inherit.cmk"
  f.write_text(src)
  return cmk("cmk", "run", str(f), env={"CMK_SUPERVISOR": "1"})


# Base + subclass that each define a `greet` member, differing only in HOW greet is
# expressed (macro vs recipe target).  The subclass's greet must win either way,
# and a non-overridden base target (`common`) must survive.
_MACRO_SRC = (
  "from cmk import class\n"
  "class Base[|\n"
  "  ${self}.greet = printf 'greet:%s\\n' base\n"
  "  ${self}.go:\n"
  "    $(${self}.greet)\n"
  "|]\n"
  "class Sub(bases=Base)[|\n"
  "  ${self}.greet = printf 'greet:%s\\n' sub\n"
  "|]\n"
  "Sub s(| |)\n"
  "demo:\n\tthis.s.go\n"
  "__main__: demo\n"
)

_RECIPE_SRC = (
  "from cmk import class\n"
  "class Base[|\n"
  "  ${self}.greet:\n"
  "    printf 'greet:%s\\n' base\n"
  "  ${self}.common:\n"
  "    printf 'common:%s\\n' base\n"
  "|]\n"
  "class Sub(bases=Base)[|\n"
  "  ${self}.greet:\n"
  "    printf 'greet:%s\\n' sub\n"
  "|]\n"
  "Sub s(| |)\n"
  "demo:\n\tthis.s.greet\n\tthis.s.common\n"
  "__main__: demo\n"
)


def test_macro_member_overrides_cleanly(cmk, tmp_path):
  # A macro-valued member: Sub reassigns the variable; linear MRO makes the derived
  # value win and make stays silent, because a variable reassignment is not a recipe
  # redefinition.
  r = run_cmk(cmk, tmp_path, _MACRO_SRC)
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "greet:sub" in r.stdout               # derived wins (linear MRO)
  assert "overriding recipe" not in out        # silent: not a recipe redefinition


def test_recipe_target_member_overrides_cleanly(cmk, tmp_path):
  # A recipe-TARGET member: `lang.class.shadowclean` strips Base's `greet` recipe from the
  # cloned body when Sub redefines it, so make sees one recipe (Sub's) and never
  # warns.  The non-overridden `common` target is inherited untouched.
  r = run_cmk(cmk, tmp_path, _RECIPE_SRC)
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "greet:sub" in r.stdout               # derived wins
  assert "greet:base" not in r.stdout          # base's greet was stripped, not just shadowed
  assert "common:base" in r.stdout             # non-overridden base target still inherited
  assert "overriding recipe" not in out        # the fix: no duplicate-recipe warning
