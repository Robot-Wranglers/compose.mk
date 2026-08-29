"""What the `import` directive does with its kwargs, and where `as` falls short.

A directive reads `import <src> [as <ns>], <kw=v..>` and lowers through the single
`ambient.dissolve` entry point, which forwards namespace=/flat=/defs=/targets= on to
the loader. A selector (`targets=`/`defs=`) imports only the matching members. The
`as` rename works for independent members and breaks on cross-references; see below.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [
  pytest.mark.unit,
  pytest.mark.compiler,
  pytest.mark.module_system,
  pytest.mark.namespace,
]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

PLUGIN = "build.a:; cmk.log(built a)\nbuild.b:; cmk.log(built b)\nship:; cmk.log(shipped)\n"
# every member above is independent; each of these leans on a sibling one way.
XREF_PREREQ_PLUGIN = "xref.setup:; cmk.log(setup ran)\nxref.build: xref.setup\n\tcmk.log(build ran)\n"
XREF_VAR_PLUGIN = (
  "xref.tag ?= plain\nxref.show:\n\tcmk.log(tag is [${xref.tag}])\n"
)
XREF_CALL_PLUGIN = (
  "xref.leaf:; cmk.log(leaf ran)\nxref.root:\n\t${make} xref.leaf\n"
)
DEFLIB = "define helper_a\n\techo HELPER_A\nendef\ndefine other_x\n\techo OTHER\nendef\n"


def _run(src, goal, tmp_path, plugin=PLUGIN):
  (tmp_path / "mylib.cmk").write_text(plugin)
  (tmp_path / "deflib.mk").write_text(DEFLIB)
  f = tmp_path / "consumer.cmk"
  f.write_text(src)
  env = {"CMK_PLUGINS_DIR": f"{tmp_path}:{REPO / '.cmk'}"}
  import os

  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(tmp_path),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=180,
    env={**os.environ, **env},
  )
  return r.stdout + r.stderr


def _transpile(src):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src.encode(),
    capture_output=True,
    timeout=120,
  )
  return r.stdout.decode(errors="replace")


def test_targets_selector_imports_only_matching_targets(tmp_path):
  # `import <plugin>, targets=<glob>` -- kwargs forwarded, build.* selected + namespaced.
  out = _run(
    "import mylib, targets='build.*'\n__main__: mylib.build.a mylib.build.b\n",
    "__main__",
    tmp_path,
  )
  assert "built a" in out and "built b" in out, out


def test_targets_selector_omits_unmatched_targets(tmp_path):
  # the unselected `ship` target is never created, so asking for it fails to resolve.
  out = _run(
    "import mylib, targets='build.*'\n__main__: mylib.ship\n",
    "__main__",
    tmp_path,
  )
  assert "shipped" not in out, out


def test_kwargs_left_of_as_are_not_a_second_source(tmp_path):
  # `import src kw=v as ns` -- the kwarg to the left of `as` is not a second source.
  out = _run(
    "import mylib as B, targets='build.*'\n__main__: B.build.a B.build.b\n",
    "__main__",
    tmp_path,
  )
  assert "built a" in out and "built b" in out, out


def test_kwargs_right_of_as_still_parse(tmp_path):
  # `import src as ns kw=v` -- the pre-existing right-of-`as` spelling still works.
  out = _run(
    "import mylib as B, targets='build.*'\n__main__: B.build.a\n",
    "__main__",
    tmp_path,
  )
  assert "built a" in out, out


def test_flat_kwarg_drops_the_namespace_prefix(tmp_path):
  # `import <plugin>, flat=1` -- extension fallback resolves it; flat drops the prefix.
  out = _run("import mylib, flat=1\n__main__: build.a\n", "__main__", tmp_path)
  assert "built a" in out, out


def test_file_path_source_with_defs_selector(tmp_path):
  # a bare (no-`as`) file PATH with a selector: `/`-charclass + smart-route guard both needed.
  probe = (
    "import %s/deflib.mk, defs='helper_*'\n"
    "probe:; @printf \"h=[%%s] o=[%%s]\\n\" "
    '"$(if $(filter undefined,$(origin helper_a)),no,yes)" '
    '"$(if $(filter undefined,$(origin other_x)),no,yes)"\n'
  ) % tmp_path
  out = _run(probe, "probe", tmp_path)
  assert "h=[yes] o=[no]" in out, out  # helper_* imported (bare), other_x excluded


# the three ways a member can reference a sibling, one xfail each so they unpin apart


@pytest.mark.xfail(
  reason="`import <src> as <ns>` renames column-0 heads and nothing else, so every "
  "reference to a renamed sibling keeps its pre-rename spelling. The passing rename "
  "tests above all use members that never reference each other, which is why this has "
  "stayed invisible. IMPORTANT: the workaround is to give anything cross-referenced a "
  "private (dot- or underscore-headed) name, which the rename skips, so the reference "
  "stays valid under either name. That is what .cmk/fossil.cmk does with its .fossil.* "
  "plumbing. The cost is that public members may not reference each other, so a public "
  "target that is also a prereq has to become a thin wrapper over a private one. "
  "Prereq case: fails at build time with `No rule to make target 'xref.setup'`.",
  strict=True,
)
def test_import_as_carries_prereq_reference(tmp_path):
  out = _run(
    "import mylib as B\n__main__: B.xref.build\n",
    "__main__",
    tmp_path,
    plugin=XREF_PREREQ_PLUGIN,
  )
  assert "setup ran" in out, out
  assert "build ran" in out, out


@pytest.mark.xfail(
  reason="a recipe's recursive call to a sibling is not renamed, so it fails only when "
  "that recipe runs, with `No rule to make target 'xref.leaf'`. IMPORTANT: a private "
  "(dot- or underscore-headed) callee sidesteps this; see the prereq case above.",
  strict=True,
)
def test_import_as_carries_recursive_call(tmp_path):
  out = _run(
    "import mylib as B\n__main__: B.xref.root\n",
    "__main__",
    tmp_path,
    plugin=XREF_CALL_PLUGIN,
  )
  assert "leaf ran" in out, out


@pytest.mark.xfail(
  reason="the quiet one: a variable reference to a sibling is not renamed, so it warns "
  "`undefined variable`, expands empty, and still exits 0. The target reports success "
  "while using an empty value, so a renamed plugin can ship broken and pass its own "
  "smoke test. IMPORTANT: a private (dot- or underscore-headed) variable sidesteps "
  "this; see the prereq case above.",
  strict=True,
)
def test_import_as_carries_variable_reference(tmp_path):
  out = _run(
    "import mylib as B\n__main__: B.xref.show\n",
    "__main__",
    tmp_path,
    plugin=XREF_VAR_PLUGIN,
  )
  assert "tag is [plain]" in out, out


def test_file_source_skips_smart_route_registration():
  # a file source skips the `cmk.import` registrar, which resolves names not filenames
  out = _transpile("import deflib.mk, defs='helper_*'\n")
  assert "cmk.import,deflib.mk" not in out, out
  assert "ambient.dissolve" in out and "defs='helper_*'" in out, out
