"""Regression: reading a class instance's own `define` body back yields a clean payload,
not lowered class machinery.

`mk.def.read/<name>` is `$(value <name>)` -- it hands back the raw `define <name>` body.  A
consumer that treats an instance's define-body as data (a payload, a transform, a template)
needs a usable value, not the lowered `$(eval define ${self}.__doc__${nl}<doc>${nl}endef)`.
Two cases guard this: an empty-body instance reads back empty, and a body carrying only a
docstring reads back as just that docstring text -- both clean.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent


def _readback(cmk, tmp_path, body):
  """Construct `thing t(| body |)`, then print `mk.def.read/t` (the instance's define-body)."""
  src = tmp_path / "rb.cmk"
  src.write_text(
    "cmk.class thing(| |)\n"
    f"thing t(| {body} |)\n"
    'probe:; @printf "READBACK=[%s]\\n" "`${make} mk.def.read/t 2>/dev/null`"\n'
    "__main__: probe\n"
  )
  r = cmk("cmk", "run", str(src), cwd=tmp_path, env={"CMK_SUPERVISOR": "1"}, timeout=120)
  assert r.returncode == 0, r.stdout + r.stderr
  out = r.stdout + r.stderr
  marker = "READBACK=["
  i = out.index(marker) + len(marker)
  return out[i : out.index("]", i)]


def test_empty_body_reads_back_clean(cmk, tmp_path):
  # CONTROL: an empty-body instance reads back as nothing -- a consumer gets a clean/absent payload.
  assert _readback(cmk, tmp_path, "") == ""


@pytest.mark.docstring
def test_docstring_body_reads_back_clean(cmk, tmp_path):
  # A docstring in the body reads back as a usable payload (nothing but the
  # docstring's own text), not raw `$(eval define ...)`.
  rb = _readback(cmk, tmp_path, "\n  '''a doc'''\n")
  assert "$(eval define" not in rb, rb
