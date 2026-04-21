"""A dsl extends code.compiled, but cooked-body `self.` config isn't consumed.

Following the Language-protocol pattern -- cook the dsl body with `[|..|]` and write
`self.key = val` -- correctly namespaces the assignment to the INSTANCE
(`${self}.key`), with NO global leak (unlike a bare `key:=val`, which leaks global;
see test_class_body_attr_scope_cmk).  So structurally a dsl CAN extend code.compiled.

The gap: code.compiled reads its per-language spec CLASS-scoped, as `$(<class>.key)`
(compose.mk ~5285 srcmap / ~5291 env+mounts / ~5361 fmtentry+base).  A cooked body's
`self.fmtentry` lands on the instance, where code.compiled never looks -- so the
build/fmt see nothing.  Fixing that means code.compiled reading spec off the instance
(src), a code.compiled change deliberately NOT made here.  Docker-free.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "dcc.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_cooked_self_config_namespaces_to_instance(tmp_path):
  # CHARACTERIZATION: `self.fmtentry` in a cooked dsl body binds the INSTANCE and
  # does NOT leak to the global namespace -- the namespacing itself is correct.
  r, out = _run_cmk(
    "import dsl.golang\n"
    "dsl.golang gc(| package main |)\n"
    "probe:; @printf 'inst=[%s] glob=[%s]' '$(gc.fmtentry)' '$(fmtentry)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "inst=[gofmt] glob=[]" in out, out


@pytest.mark.xfail(reason=(
  "code.compiled reads per-language config CLASS-scoped ($(<class>.fmtentry), "
  "compose.mk:5361); a cooked dsl body's `self.fmtentry` lands on the INSTANCE, so "
  "the build/fmt never see it -- code.compiled would have to read spec off the src "
  "(instance) for cooked-body config to be consumed"), strict=True)
def test_code_compiled_reads_cooked_self_config(tmp_path):
  # DESIRED: config a dsl declares in its cooked body is visible where code.compiled
  # reads it. code.compiled reads $(<class>.fmtentry); the body's self.fmtentry is
  # on the instance, so the class read is empty today.
  r, out = _run_cmk(
    "import dsl.golang\n"
    "dsl.golang gc(| package main |)\n"
    "probe:; @printf 'code-compiled-sees=[%s]' '$(dsl.golang.fmtentry)'\n"
    "__main__: probe\n", tmp_path)
  assert r.returncode == 0, out
  assert "code-compiled-sees=[gofmt]" in out, out
