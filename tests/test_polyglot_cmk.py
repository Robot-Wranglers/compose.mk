"""Tests for the .cmk/polyglot.golang.cmk plugin -- the reusable `cmk.polyglot.golang.lambda(src=..
mod=.. ..)` macro -- via its client demo demos/cmk/golang-lambda.cmk.

The macro expands to a `build-if-needed && exec "$bin" <args>` shell string: on first use it
cross-builds the inline Go block-refs in the dockerized toolchain and caches the binary under
${CMK_XDG_CACHE}/<hash>/<name>; afterwards it is a cache HIT.  The build needs docker, so the
build+run case is marked slow/integration; the import-cleanly case is a cheap unit smoke (it guards
the module-staging regression where a `#`-terminated define line ate the following `endef`).
"""

import re
import subprocess
from pathlib import Path

import pytest

# polyglot.golang.cmk is a plugin -- collect this whole file into the `plugin` suite too (on top of
# each test's own unit / docker markers).
pytestmark = pytest.mark.plugin

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "golang-lambda.cmk"
PLUGIN = REPO / ".cmk" / "polyglot.golang.cmk"


def _dec(b):
  return b.decode("utf-8", "replace") if isinstance(b, (bytes, bytearray)) else (b or "")


def _strip(s):
  return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)


@pytest.mark.unit
def test_polyglot_imports_cleanly():
  # Staging regression guard: no define may end in `#` (that eats the endef during minified module
  # staging -> "missing 'endef', unterminated 'define'").  Compiling the plugin must lower every
  # polyglot define, each with a matching endef.
  r = subprocess.run(
    [str(REPO / "compose.mk"), "mk.compile"],
    cwd=str(REPO),
    input=PLUGIN.read_bytes(),
    capture_output=True,
    timeout=60,
  )
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  assert "unterminated" not in out, out
  for d in ("_polyglot.golang.build", "_polyglot.golang.build.sh", "polyglot.golang.ensure", "polyglot.golang.lambda"):
    assert f"define {d}\n" in out, (d, out)
  # at least one endef per define (the regression turned N defines into N-1 endefs)
  assert out.count("\nendef") >= out.count("\ndefine "), out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_polyglot_golang_builds_and_runs():
  # First run cross-builds in docker (or cache HIT if already built), then execs the binary.
  r = subprocess.run(
    [str(DEMO)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=300,
  )
  out = _strip(_dec(r.stdout) + _dec(r.stderr))
  assert r.returncode == 0, out
  assert "hello world, from polyglot.golang!" in out, out
  # the cache log fires either way (MISS+built on the first run, HIT afterwards)
  assert "polyglot.golang" in out and ("cache" in out), out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_polyglot_golang_forwards_argv():
  # the parametric `<namespace>/%` form (here namespace=hello) forwards its stem to the binary's argv.
  r = subprocess.run(
    [str(DEMO), "hello/you"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=300,
  )
  out = _strip(_dec(r.stdout) + _dec(r.stderr))
  assert r.returncode == 0, out
  assert "hello you, from polyglot.golang!" in out, out
