"""Partial `import`/`open` directive: kwargs land through the `ambient.dissolve` seam.

Directives use a comma trailer -- `import <src> [as <ns>], <kw=v..>` -- lowering through
the one `ambient.dissolve` seam, which forwards the kwargs (namespace=/flat=/defs=/targets=)
to the loader.  A bare plugin name resolves via `_ambient.pathsrc` (with the `.cmk`/`.mk`
extension fallback); a `/`-bearing token is a verbatim path.

Selection is materialized by the `mk.select.{targets,defs}` stage: `targets=<glob>` extracts
matching target blocks (needs the `_cmk_blk_target_extract` awk, exported AFTER its define),
`defs=<glob>` matching defines.  These run a real partial import and assert the selected
members land (namespaced for targets, bare for defines) and unselected ones do not.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

PLUGIN = "build.a:; cmk.log(built a)\nbuild.b:; cmk.log(built b)\nship:; cmk.log(shipped)\n"
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


def test_plugin_targets_glob_selects_and_namespaces(tmp_path):
  # `import <plugin> targets=<glob>` -- kwargs forwarded, build.* selected + namespaced.
  out = _run("import mylib, targets='build.*'\n__main__: mylib.build.a mylib.build.b\n", "__main__", tmp_path)
  assert "built a" in out and "built b" in out, out


def test_plugin_targets_glob_excludes_unselected(tmp_path):
  # the unselected `ship` target is never created, so asking for it fails to resolve.
  out = _run("import mylib, targets='build.*'\n__main__: mylib.ship\n", "__main__", tmp_path)
  assert "shipped" not in out, out


def test_kwargs_before_as_not_a_phantom_source(tmp_path):
  # `import src kw=v as ns` -- the kwarg to the left of `as` is not a second source.
  out = _run("import mylib as B, targets='build.*'\n__main__: B.build.a B.build.b\n", "__main__", tmp_path)
  assert "built a" in out and "built b" in out, out


def test_kwargs_after_as(tmp_path):
  # `import src as ns kw=v` -- the pre-existing right-of-`as` spelling still works.
  out = _run("import mylib as B, targets='build.*'\n__main__: B.build.a\n", "__main__", tmp_path)
  assert "built a" in out, out


def test_plugin_flat_kwarg_forwarded(tmp_path):
  # `import <plugin> flat=1` -- extension fallback resolves the plugin; flat drops the prefix.
  out = _run("import mylib, flat=1\n__main__: build.a\n", "__main__", tmp_path)
  assert "built a" in out, out


def test_file_path_defs_partial_bare(tmp_path):
  # a bare (no-`as`) file PATH with a selector: `/`-charclass + smart-route guard both needed.
  probe = (
    "import %s/deflib.mk, defs='helper_*'\n"
    "probe:; @printf \"h=[%%s] o=[%%s]\\n\" "
    '"$(if $(filter undefined,$(origin helper_a)),no,yes)" '
    '"$(if $(filter undefined,$(origin other_x)),no,yes)"\n'
  ) % tmp_path
  out = _run(probe, "probe", tmp_path)
  assert "h=[yes] o=[no]" in out, out  # helper_* imported (bare), other_x excluded


def test_file_source_skips_smart_route_registration():
  # a `.mk`/`.cmk` source must NOT emit `cmk.import` (that registrar resolves namespace names,
  # not filenames) -- but the kwargs still lower to a real dissolve.
  out = _transpile("import deflib.mk, defs='helper_*'\n")
  assert "cmk.import,deflib.mk" not in out, out
  assert "ambient.dissolve" in out and "defs='helper_*'" in out, out
