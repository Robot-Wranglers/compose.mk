"""The blockref glyph: self-token operands and the `__blockref__` dunder dispatch.

`⬦NAME` (the FD blockref glyph) lowers via the `.awk.blockref` stage to materialize NAME as a
process-sub `<(..)` FD.  Two properties are pinned here:

1. The name-scan crosses a self-token operand (`⬦${self}` / `⬦${self}.shape`).  The bare char-class
   `[A-Za-z0-9._/-]` would stop at the `$` of `${self}`; the stage is injected with a `@@TOKEN_SELF@@`
   placeholder so the self-token is taken as part of the operand.  Same gap `lang.rex.name` had for
   callforms/receivers.

2. `⬦X` is dispatched through `X.__blockref__` (its declared materializable representation) when X
   has one, else X is materialized directly -- the blockref analogue of the call dunder.  A Fragment
   declares `__blockref__` bottoming out at its shape, so `⬦${self}` on a fragment resolves to its
   shape without the call site naming `.shape`.
"""

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

FD = "⬦"  # the FD blockref glyph


def test_blockref_plain_name_lowers(sandbox):
  # a plain-name operand is a def, materialized as-is (no dunder dispatch -- that is object-only).
  r = sandbox.compile("cmk.class F(|\n  ${self}.a = " + FD + "foo\n|)")
  assert r.compiled is not None, r.output
  assert "<($(call _mk.def.to.fd, foo))" in r.compiled, r.compiled


def test_blockref_crosses_self_token(sandbox):
  # the name-scan crosses `${self}.shape` whole (would otherwise stop at the `$`).
  r = sandbox.compile("cmk.class F(|\n  ${self}.a = " + FD + "${self}.shape\n|)")
  assert r.compiled is not None, r.output
  assert "${self}.shape.__blockref__" in r.compiled, r.compiled


def test_blockref_dispatches_through_dunder(sandbox):
  # `⬦${self}` (the object) dispatches through its `__blockref__`, not a hardcoded member.
  r = sandbox.compile("cmk.class F(|\n  ${self}.a = " + FD + "${self}\n|)")
  assert r.compiled is not None, r.output
  assert "$(call ${self}.__blockref__)" in r.compiled, r.compiled
