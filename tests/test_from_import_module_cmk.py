"""`from x import y` over a disk plugin module: the module loads flat, each listed
name really binds (qualified `x.y` becomes bare `y`; already-bare members pass),
and an unknown member or module faults instead of silently succeeding."""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler, pytest.mark.module_system]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

BARE_PLUGIN = "greet:; cmk.log(greeted)\nother:; cmk.log(othered)\n"
QUALIFIED_PLUGIN = (
  "mylib.greet:; cmk.log(greeted)\n"
  "mylib.hello=hi-$(strip ${1})\n"
  "mylib.wave.short=o/\n"
  "mylib.wave.long=$(strip ${1}) waves back\n"
)


def _run(src, goal, tmp_path, plugin=BARE_PLUGIN):
  (tmp_path / "mylib.cmk").write_text(plugin)
  f = tmp_path / "consumer.cmk"
  f.write_text(src)
  env = {"CMK_PLUGINS_DIR": f"{tmp_path}:{REPO / '.cmk'}"}
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
  return r.returncode, r.stdout + r.stderr


def _transpile(src):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src.encode(),
    capture_output=True,
    timeout=120,
  )
  return r.stdout.decode(errors="replace")


def test_from_disk_module_lowers_to_dispatcher():
  # core and disk names lower identically; the compiler no longer gates on module kind.
  out = _transpile("from mylib import greet\nfrom cmk import class\n")
  assert "$(call lang.module.from,mylib,greet)" in out, out
  assert "$(call lang.module.from,cmk,class)" in out, out


def test_from_disk_module_bare_member_runs(tmp_path):
  rc, out = _run("from mylib import greet\n__main__: greet\n", "__main__", tmp_path)
  assert rc == 0, out
  assert "missing separator" not in out, out
  assert "greeted" in out, out


def test_from_disk_module_loads_whole_module(tmp_path):
  # the module loads flat, so an unlisted sibling stays reachable by its declared name.
  rc, out = _run("from mylib import greet\n__main__: other\n", "__main__", tmp_path)
  assert rc == 0, out
  assert "othered" in out, out


def test_from_disk_module_members_keep_siblings(tmp_path):
  # a bound macro whose body calls an unlisted sibling still expands correctly.
  (tmp_path / "macrolib.cmk").write_text(
    "helper=inner-$(strip ${1})\nouter=wrapped[$(call helper,${1})]\n"
  )
  probe = (
    "from macrolib import outer\n"
    'probe:; @printf "outer=[%s]\\n" "$(call outer,zz)"\n'
    "__main__: probe\n"
  )
  rc, out = _run(probe, "__main__", tmp_path)
  assert rc == 0, out
  assert "outer=[wrapped[inner-zz]]" in out, out


def test_from_disk_module_binds_qualified_target_bare(tmp_path):
  # the module declares `mylib.greet`; the import makes bare `greet` a real goal.
  rc, out = _run(
    "from mylib import greet\n__main__: greet\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc == 0, out
  assert "greeted" in out, out


def test_from_disk_module_binds_qualified_macro_bare(tmp_path):
  rc, out = _run(
    "from mylib import hello\n"
    'probe:; @printf "hello=[%s]\\n" "$(call hello,zz)"\n'
    "__main__: probe\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc == 0, out
  assert "hello=[hi-zz]" in out, out


def test_from_disk_module_binds_qualified_family_bare(tmp_path):
  # binding `wave` carries the whole `mylib.wave.*` family across, like a class would.
  rc, out = _run(
    "from mylib import wave\n"
    'probe:; @printf "short=[%s] long=[%s]\\n" "${wave.short}" "$(call wave.long,zz)"\n'
    "__main__: probe\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc == 0, out
  assert "short=[o/] long=[zz waves back]" in out, out


def test_from_disk_module_legacy_qualified_spelling_still_runs(tmp_path):
  rc, out = _run(
    "from mylib import mylib.greet\n__main__: mylib.greet\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc == 0, out
  assert "greeted" in out, out


def test_from_disk_module_missing_member_faults(tmp_path):
  rc, out = _run("from mylib import nosuch\n__main__: greet\n", "__main__", tmp_path)
  assert rc != 0, out
  assert "MODULE_MEMBER" in out, out
  assert "nosuch" in out, out


def test_from_disk_module_missing_qualified_member_faults(tmp_path):
  rc, out = _run(
    "from mylib import mylib.nosuch\n__main__: mylib.greet\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc != 0, out
  assert "MODULE_MEMBER" in out, out


@pytest.mark.xfail(
  reason="`from <mod> import <member> as <alias>` is unimplemented. The dialect awk's "
  "`from` branch does not strip the `as` trailer, so the directive lowers to "
  "`$(call lang.module.from,mylib,mylib as B)` and the binder faults with MODULE_MEMBER "
  "on `as` and `B` read as member names. The receiver scanner already extracts the alias, "
  "so the grammar is half-present. `import mylib as B` is the spelling that works today. "
  "Fix needs the trailer stripped plus an alias mode in _lang.module.from.bind.",
  strict=True,
)
def test_from_disk_module_alias_mounts_namespace(tmp_path):
  # the aliased from-import should mount the module under B, like `import mylib as B` does.
  rc, out = _run(
    "from mylib import mylib as B\n__main__: B.greet\n",
    "__main__",
    tmp_path,
    plugin=QUALIFIED_PLUGIN,
  )
  assert rc == 0, out
  assert "greeted" in out, out


def test_from_missing_module_faults(tmp_path):
  rc, out = _run("from nolib import greet\n__main__: greet\n", "__main__", tmp_path)
  assert rc != 0, out
  assert "MODULE_MISSING" in out, out
