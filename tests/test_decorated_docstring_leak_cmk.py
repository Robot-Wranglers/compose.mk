"""A docstring on a DECORATED target leaks into the recipe as a runtime statement.

A leading `'''docstring'''` on a plain target is inert: the `moduledoc` stage
lifts it out of the recipe and lowers it to an `@#` make comment.  Put a
decorator above that same target and the docstring is no longer inert -- it
lowers to a live `printf '%s' '<docstring>'` in the recipe body, printing the
prose to stdout every time the target runs.

The cause is stage ordering: `decorators` relocates the `@`-decorator to the
head of the recipe BEFORE `moduledoc` runs, so the docstring is no longer the
first recipe line and moduledoc no longer recognises it, leaving it to lower as
an ordinary inline string statement.

The practical fallout (recorded by demos/cmk/dirhandler.cmk, the prototype this
guards): a decorated target must be documented with a `#` comment above the
decorator, never a body docstring.  Promoting `io.dirhandler` into core should
either fix the ordering or make the compiler reject the combination.
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


@pytest.mark.xfail(
  reason="the decorators stage relocates the decorator ahead of the docstring "
  "before moduledoc runs, so the docstring is no longer first and lowers to a "
  "live `printf '%s' '<docstring>'` that leaks to stdout instead of an inert "
  "`@#` comment",
  strict=True,
)
def test_decorated_target_docstring_is_inert(ir):
  # REPRO: identical but for the decorator above the target.  Desired: the
  # docstring stays inert exactly as in the control (no runtime `printf '%s'`).
  recipe = _recipe(ir, decorated=True)
  assert "printf '%s'" not in recipe, recipe
