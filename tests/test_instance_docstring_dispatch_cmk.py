"""A docstring in an instance's construction body breaks the whole program.

An instance minted with an EMPTY body builds and dispatches its class methods
fine (`this.t.hello` runs).  Add nothing but a `'''docstring'''` to that body and
the program no longer builds: the docstring lowers into the instance's construction
in a way that corrupts the generated makefile.  The symptom varies with the class
hierarchy -- here a bare `cmk.class` yields a compile-time SyntaxError at
`mk.validate`; in a richer hierarchy (e.g. the `agent` composition in
demos/cmk/jqd.cmk) it surfaces instead as `this.<instance>.<method>: command not
found`, the `this.` dispatch never lowering.

This is the dispatch/build face of the same defect that
test_agent_body_xform_cmk.py records from the readback angle (an instance's
define-body reads back as lowered `$(eval define ${self}.__doc__...)` machinery
once the body is non-empty).  The practical fallout: instances must be documented
with a `#` comment, never a body docstring.
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


@pytest.mark.xfail(
  reason="a docstring in an instance construction body corrupts the instance's "
  "lowered define, so the program fails to build/dispatch: `this.t.hello` never "
  "runs (bare cmk.class => compile SyntaxError; richer hierarchies => "
  "`this.<instance>.method: command not found`)",
  strict=True,
)
def test_docstring_body_instance_dispatches(cmk, tmp_path):
  # REPRO: identical to the control but for a docstring in the body.  Desired: the
  # docstring is inert w.r.t. construction and dispatch works exactly as above.
  r = _dispatch(cmk, tmp_path, "'''a doc'''")
  assert r.ok and "HELLO-DISPATCHED" in (r.stdout + r.stderr), r.stdout + r.stderr
