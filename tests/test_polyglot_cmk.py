"""Tests for the .cmk/dsl.golang.cmk plugin -- the `dsl.golang` kind + the shared
cmk.code.compiled.lambda(lang=dsl.golang ..) macro -- via its client demo demos/cmk/golang.cmk.

The macro expands to a `build-if-needed && exec "$bin" <args>` shell string: on first use it
cross-builds the inline Go block-refs in the dockerized toolchain and caches the binary under
${CMK_XDG_CACHE}/<hash>/<name>; afterwards it is a cache HIT.  The build needs docker, so the
build+run case is marked slow/integration; the import-cleanly case is a cheap unit smoke (it guards
the module-staging regression where a `#`-terminated define line ate the following `endef`).
"""

import os
import re
import subprocess
import time
from pathlib import Path

import pytest

# a plugin file -- also collect the whole file into the plugin suite.
pytestmark = [pytest.mark.external_plugin, pytest.mark.plugin, pytest.mark.covers_demo("golang.cmk")]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "golang.cmk"
PLUGIN = REPO / ".cmk" / "dsl.golang.cmk"


def _compile(plugin_path):
  # lower a plugin through the cmk compiler; return (rc, combined-output).
  r = subprocess.run(
    [str(REPO / "compose.mk"), "mk.compile"],
    cwd=str(REPO),
    input=plugin_path.read_bytes(),
    capture_output=True,
    timeout=60,
  )
  return r.returncode, _dec(r.stdout) + _dec(r.stderr)


def _assert_staging_clean(out):
  # Staging regression guard: no define may end in `#` (that eats the endef during minified module
  # staging -> "missing 'endef', unterminated 'define'").  Every define needs a matching endef.
  assert "unterminated" not in out, out
  assert out.count("\nendef") >= out.count("\ndefine "), out


def _dec(b):
  return (
    b.decode("utf-8", "replace")
    if isinstance(b, (bytes, bytearray))
    else (b or "")
  )


def _strip(s):
  return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)


@pytest.mark.unit
def test_skeleton_is_core_resident():
  # The generic cross-build skeleton was promoted from a plugin into __hosted__ core (the golang +
  # rust shims delegate here).  It must resolve with NO plugin import: a code.compiled.* target
  # runs straight from core (proving the hosted partition compiled the promoted block).
  r = subprocess.run(
    [str(REPO / "compose.mk"), "code.compiled.cache.list"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=60,
  )
  out = _strip(_dec(r.stdout) + _dec(r.stderr))
  assert r.returncode == 0, out
  assert ("cksum entries" in out) or ("no cache" in out), out


@pytest.mark.unit
def test_cache_gc_evicts_oldest_via_safe_move_spares_non_cksum(tmp_path):
  # docker-free: seed a fake cache with 12 numeric (cksum) dirs + non-cksum dirs, run cache.gc, and
  # assert it keeps the newest KEEP numeric, evicts the rest via a safe mv into a self-cleaning
  # io.mktempd (no recursive-force delete of a variable path), and never touches the non-cksum entries.
  cache = tmp_path / "cache"
  cache.mkdir()
  (cache / "bin").mkdir()  # non-cksum -- must survive
  (cache / "keepme").mkdir()  # non-cksum -- must survive
  base = time.time()
  for i in range(1, 13):
    d = cache / f"{i:010d}"
    d.mkdir()
    os.utime(d, (base + i, base + i))  # deterministic mtimes: dir 1 oldest .. dir 12 newest
  prog = tmp_path / "p.cmk"
  prog.write_text("import dsl.golang\n")
  r = subprocess.run(
    [str(REPO / "compose.mk"), "cmk", "run", str(prog), "code.compiled.cache.gc"],
    cwd=str(REPO),
    env={**os.environ, "CMK_XDG_CACHE": str(cache), "_CMK_COMPILE_CACHE_KEEP": "10"},
    capture_output=True,
    timeout=120,
  )
  out = _dec(r.stdout) + _dec(r.stderr)
  assert r.returncode == 0, out
  survivors = sorted(p.name for p in cache.iterdir())
  # non-cksum dirs untouched; exactly the newest 10 numeric remain (oldest 2 evicted)
  assert "bin" in survivors and "keepme" in survivors, survivors
  assert sorted(n for n in survivors if n.isdigit()) == [f"{i:010d}" for i in range(3, 13)], (survivors, out)
  # the 2 oldest are gone and the self-cleaning temp dir left nothing behind
  assert "0000000001" not in survivors and "0000000002" not in survivors, survivors
  assert not any(n.startswith(".tmp") for n in survivors), survivors


@pytest.mark.unit
def test_polyglot_imports_cleanly():
  # go shim keeps its build define and declares the golang kind on the compiled base.
  rc, out = _compile(PLUGIN)
  assert rc == 0, out
  _assert_staging_clean(out)
  assert "define _dsl.golang.build.sh\n" in out, out
  assert "declare.code" not in out, out
  for sym in ("define dsl.golang.default.mod", "$(call dsl, def=golang", "self.buildsh = _dsl.golang.build.sh"):
    assert sym in out, (sym, out)


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
  assert "hi world!" in out, out
  # the cache log fires either way (MISS+built on the first run, HIT afterwards)
  assert "dsl.golang" in out and ("cache" in out), out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_polyglot_golang_forwards_argv():
  # the instance's parametric stem form (here hello/you) forwards its stem to the binary argv.
  r = subprocess.run(
    [str(DEMO), "hello/you"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=300,
  )
  out = _strip(_dec(r.stdout) + _dec(r.stderr))
  assert r.returncode == 0, out
  assert "hi you!" in out, out
