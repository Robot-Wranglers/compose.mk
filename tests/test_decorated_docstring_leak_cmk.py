"""A body docstring is inert on a decorated target, exactly as on a plain one.

A leading `'''docstring'''` lifts out of the recipe to an `@#` make comment, and
a decorator above the target does not change that.  The `decorators` stage
relocates the `@`-decorator to the recipe head before `moduledoc` runs, so
moduledoc holds that line back to keep the docstring in first position; the
lifted `@#` stays the first recipe line, where joinbody preserves it verbatim.

Without that, the displaced docstring lowered to a live `printf '%s'` that
printed the prose to stdout on every run.
"""

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.docstring]


def _recipe(ir, *, decorated):
  """Compile a `process/%` target carrying a body docstring (with or without a
  decorator above it) and return its lowered recipe text."""
  src = (
    "deco=true\n"
    + ("@deco\n" if decorated else "")
    + "process/%:\n"
    + "    '''DOC-MARKER for the target.'''\n"
    + "    printf 'body\\n'\n"
  )
  return ir(src).rule("process/%")


def test_plain_target_docstring_is_inert(ir):
  # CONTROL: undecorated, the docstring lifts to an `@#` comment and never
  # becomes a runtime statement; the body still runs.
  recipe = _recipe(ir, decorated=False)
  assert "printf '%s'" not in recipe, recipe
  assert "@# DOC-MARKER for the target." in recipe, recipe
  assert "printf 'body" in recipe, recipe


def test_decorated_target_docstring_is_inert(ir):
  # REPRO: identical but for the decorator above the target.  Desired: the
  # docstring stays inert exactly as in the control (no runtime `printf '%s'`).
  recipe = _recipe(ir, decorated=True)
  assert "printf '%s'" not in recipe, recipe
  assert "@# DOC-MARKER for the target." in recipe, recipe
