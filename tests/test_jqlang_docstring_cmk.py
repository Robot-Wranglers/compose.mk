"""Docstring support for `dsl.jqlang` (raw-shape fragment bananas).

A leading `'''..'''` in a jqlang banana must not compromise the jq `.shape`.  The
`moduledoc` compile stage LIFTS it: for a banana whose kind is in FRAGKINDS
(`_cmk.doc.kinds`, e.g. `jqlang`/`dsl.jqlang`) it emits a sibling
`$(eval define <name>.__doc__ ..)` AFTER the banana and drops the docstring from the
body, so the shape cooks clean.  Binding `<name>.__doc__` is a free bonus of that lift.
No runtime cost, no files.  Docker-free (jq / make only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.docstring]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, src):
  f = tmp_path / "jqdoc.cmk"
  f.write_text(src)
  return subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )


def test_single_line_docstring_cleans_shape_and_binds_doc(tmp_path):
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang addone(|\n"
    "  '''adds one to .n'''\n"
    "  .n + 1\n"
    "|)\n"
    "$(info DOC<<${addone.__doc__}>>)\n"
    "$(info SHAPE<<${addone.shape}>>)\n"
    "__main__:; @true\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "DOC<<adds one to .n>>" in out, out       # docstring lifted -> __doc__
  assert "SHAPE<<.n + 1>>" in out, out             # shape is pure jq (no carrier, no eval)
  assert "eval define" not in out.split("SHAPE<<")[1].split(">>")[0], out


def test_multiline_docstring(tmp_path):
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang wrap(|\n"
    "  '''\n"
    "  line one\n"
    "  line two\n"
    "  '''\n"
    "  { r: . }\n"
    "|)\n"
    "$(info DOC1<<$(firstword ${wrap.__doc__})>>)\n"
    "$(info SHAPE<<${wrap.shape}>>)\n"
    "__main__:; @true\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "DOC1<<line>>" in out, out                # __doc__ carries the (multi-line) text
  assert "{ r: . }" in out, out                    # shape survives, docstring gone


def test_no_docstring_is_byte_identical(tmp_path):
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang plain(| . * 2 |)\n"
    "$(info SHAPE<<${plain.shape}>>)\n"
    "__main__:; @true\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "SHAPE<<. * 2>>" in out, out


def test_documented_fragment_runs_and_composes(tmp_path):
  # The clean shape actually runs, and composition (`|`) carries pure jq (no carrier leak):
  # the docstring'd `addone` folds with `double` exactly like an undocumented leaf.
  p = _run(
    tmp_path,
    "import io\n"
    "from cmk import dsl\n"
    "dsl.jqlang addone(|\n"
    "  '''adds one to .n'''\n"
    "  .n + 1\n"
    "|)\n"
    "dsl.jqlang double(| . * 2 |)\n"
    "&pipeline <- addone|double\n"
    "demo:; io.json_builder(n:raw=4) | this.pipeline\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "10" in p.stdout, out                      # {n:4} -> .n+1 = 5 -> .*2 = 10


def test_composition_of_two_documented_fragments(tmp_path):
  # Both leaves carry a docstring; the `|` fold must still see pure jq in each `.shape` (both
  # docstrings lifted out) so the composite runs -- and both `__doc__`s bind.
  p = _run(
    tmp_path,
    "import io\n"
    "from cmk import dsl\n"
    "dsl.jqlang addone(|\n"
    "  '''adds one to .n'''\n"
    "  .n + 1\n"
    "|)\n"
    "dsl.jqlang double(|\n"
    "  '''doubles the value'''\n"
    "  . * 2\n"
    "|)\n"
    "&pipeline <- addone|double\n"
    "$(info DOCS<<${addone.__doc__}|${double.__doc__}>>)\n"
    "demo:; io.json_builder(n:raw=4) | this.pipeline\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "DOCS<<adds one to .n|doubles the value>>" in out, out   # both docstrings lifted
  assert "10" in p.stdout, out                                    # {n:4} -> .n+1 = 5 -> .*2 = 10


def test_multiline_jq_shape_with_docstring(tmp_path):
  # Regression for the make-`$(eval X := multiline)` trap: a MULTI-LINE jq shape carrying a
  # docstring must not leak its 2nd+ lines to make top-level ("multiple target patterns").
  # The lift keeps the shape a single clean cooked define.
  p = _run(
    tmp_path,
    "import io\n"
    "from cmk import dsl\n"
    "dsl.jqlang shape(|\n"
    "  '''builds an object'''\n"
    "  { a: .n,\n"
    "    b: (.n + 1) }\n"
    "|)\n"
    "demo:; io.json_builder(n:raw=7) | shape()\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a": 7' in p.stdout or '"a":7' in p.stdout, out
  assert '"b": 8' in p.stdout or '"b":8' in p.stdout, out
