"""A docstring in an instance's construction body is inert w.r.t. construction.

An instance minted with an empty body builds and dispatches its class methods
(`this.t.hello` runs), and a body holding nothing but a `'''docstring'''`
behaves identically: moduledoc lifts the docstring out to a sibling
`<name>.__doc__` and leaves an empty construction body behind.

The one-line banana spelling used here once missed that lift, leaving the raw
triple-quote inside the instance's define.  A bare `cmk.class` then failed at
`mk.validate` with a SyntaxError, and richer hierarchies failed at dispatch with
`this.<instance>.<method>: command not found`.
"""

from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.docstring]

REPO = Path(__file__).resolve().parent.parent


def _dispatch(cmk, tmp_path, body):
  """Mint `thing t(| body |)` (thing has a `.hello` method), then dispatch it via
  `this.t.hello` from another target.  Returns the run Result."""
  src = tmp_path / "disp.cmk"
  src.write_text(
    "cmk.class thing(| ${self}.hello:; echo HELLO-DISPATCHED |)\n"
    f"thing t(| {body} |)\n"
    "caller:\n"
    "  this.t.hello\n"
    "__main__: caller\n"
  )
  return cmk(
    "cmk", "run", str(src), cwd=tmp_path, env={"CMK_SUPERVISOR": "1"}, timeout=120
  )


def test_empty_body_instance_dispatches(cmk, tmp_path):
  # CONTROL: an empty-body instance builds and dispatches its method.
  r = _dispatch(cmk, tmp_path, "")
  assert r.ok and "HELLO-DISPATCHED" in (r.stdout + r.stderr), r.stdout + r.stderr


def test_docstring_body_instance_dispatches(cmk, tmp_path):
  # REPRO: identical to the control but for a docstring in the body.  Desired: the
  # docstring is inert w.r.t. construction and dispatch works exactly as above.
  r = _dispatch(cmk, tmp_path, "'''a doc'''")
  assert r.ok and "HELLO-DISPATCHED" in (r.stdout + r.stderr), r.stdout + r.stderr


KIND = "cmk.class thing(| ${self}.hello:; echo HI |)\n"


@pytest.mark.parametrize(
  "one,multi,name",
  [
    pytest.param(
      "thing t(| '''a doc''' |)\n",
      "thing t(|\n  '''a doc'''\n|)\n",
      "t",
      id="plain",
    ),
    pytest.param(
      "thing t(kw=v)(| '''a doc''' |)\n",
      "thing t(kw=v)(|\n  '''a doc'''\n|)\n",
      "t",
      id="ctor-kwargs",
    ),
    pytest.param(
      "* mod(|\n  thing inner(| '''a doc''' |)\n|)\n",
      "* mod(|\n  thing inner(|\n    '''a doc'''\n  |)\n|)\n",
      "inner",
      id="nested",
    ),
  ],
)
def test_oneline_lift_matches_multiline(ir, one, multi, name):
  # both spellings of a doc-bearing banana lower identically, at any nesting depth.
  a, b = ir(KIND + one).stdout, ir(KIND + multi).stdout
  assert "$(eval define %s.__doc__${nl}a doc${nl}endef)" % name in a, a
  assert "'''a doc'''" not in a, a
  assert a == b, a


def test_oneline_assign_body_is_payload(ir):
  # an assign banana carries payload, never a docstring.
  r = ir("payload = (| '''not a doc''' |)\n")
  assert "'''not a doc'''" in r.stdout, r.stdout
  assert "payload.__doc__" not in r.stdout, r.stdout
