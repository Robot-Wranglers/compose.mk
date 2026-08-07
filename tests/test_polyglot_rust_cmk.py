"""Tests for the .cmk/dsl.rust.cmk plugin -- the ~15-line Rust shim over the generic
code.compiled cross-build skeleton (now resident in __hosted__ core).

These build a minimal Rust program inline via native two-paren construction
`dsl.rust NAME(| body |)` and run it through `cmk run`, asserting the real behavior of the
generated surface: the `NAME` run target, the `NAME/%` argv target, and the bare-instance
callable form `NAME(args=..)` (which dispatches through the generated `NAME.__call__`).  Each
test owns its fixture -- it does not depend on any demo file.  The cross-build needs docker
(slow/integration); the import-cleanly case is a docker-free unit smoke.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.external_plugin, pytest.mark.plugin]

REPO = Path(__file__).resolve().parent.parent
PLUGIN = REPO / ".cmk" / "dsl.rust.cmk"

# A minimal Rust program built via native construction.  `unwrap_or` (not the `|| ..` closure
# form) keeps the source free of `(|`/`|)` sequences that would collide with banana delimiters.
# `viacall` exercises the bare-instance callable form; `__main__` is unused (goals are explicit).
PROGRAM = """import dsl.rust

dsl.rust greeter(|
fn main() {
    let who = std::env::args().nth(1).unwrap_or("world".to_string());
    println!("hi {}!", who);
}
|)

viacall:
    greeter(args=team)

__main__: greeter
"""


def _dec(b):
  return b.decode("utf-8", "replace") if isinstance(b, (bytes, bytearray)) else (b or "")


def _strip(s):
  return re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", s)


def _run(tmp_path, *goals):
  # Build the fixture program, then run the given goals through `cmk run` (cwd=REPO so the
  # `import code.rust` resolves against the plugin dir).
  prog = tmp_path / "prog.cmk"
  prog.write_text(PROGRAM)
  r = subprocess.run(
    [str(REPO / "compose.mk"), "cmk", "run", str(prog), *goals],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=590,
  )
  return r.returncode, _strip(_dec(r.stdout) + _dec(r.stderr))


@pytest.mark.unit
def test_rust_imports_cleanly():
  # Staging regression guard + the shim keeps its language build.sh and the native ctor (no declare.*).
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
  assert out.count("\nendef") >= out.count("\ndefine "), out
  assert "define _dsl.rust.build.sh\n" in out, out
  assert "declare.code" not in out, out
  for sym in ("define dsl.rust.default.cargo", "$(call dsl, def=rust", "self.buildsh = _dsl.rust.build.sh"):
    assert sym in out, (sym, out)


@pytest.mark.docker
@pytest.mark.needs_docker
def test_rust_native_construction_builds_and_runs(tmp_path):
  # `code.rust greeter(| body |)` cross-builds in the cargo container and wires a `greeter` target.
  rc, out = _run(tmp_path, "greeter")
  assert rc == 0, out
  assert "hi world!" in out, out
  # the shared cache log fires either way (MISS+built on the first run, HIT afterwards)
  assert "dsl.rust" in out and "cache" in out, out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_rust_argv_target_forwards_stem(tmp_path):
  # the generated `<ns>/%` target forwards its stem to the binary's argv.
  rc, out = _run(tmp_path, "greeter/you")
  assert rc == 0, out
  assert "hi you!" in out, out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_rust_instance_is_callable(tmp_path):
  # the bare-instance callform `greeter(args=team)` dispatches through the generated
  # `<ns>.__call__` and forwards its kwargs to the binary's argv.
  rc, out = _run(tmp_path, "viacall")
  assert rc == 0, out
  assert "hi team!" in out, out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_rust_cache_miss_then_hit_stable_path(tmp_path):
  # An isolated per-test cache: the first run is a guaranteed cold MISS, the second a HIT, and the
  # binary lives under exactly ONE cksum dir both times (a stable content-hash).  Guards the
  # cache/memo path against the helper-extraction refactor (which is not byte-diffable).
  cache = tmp_path / "xdg"
  cache.mkdir()
  prog = tmp_path / "prog.cmk"
  prog.write_text(PROGRAM)

  def run():
    r = subprocess.run(
      [str(REPO / "compose.mk"), "cmk", "run", str(prog), "greeter"],
      cwd=str(REPO),
      stdin=subprocess.DEVNULL,
      env={**os.environ, "CMK_XDG_CACHE": str(cache)},
      capture_output=True,
      timeout=590,
    )
    return r.returncode, _strip(_dec(r.stdout) + _dec(r.stderr))

  rc1, out1 = run()
  assert rc1 == 0 and "hi world!" in out1, out1
  assert "not found" in out1, out1  # cold cache -> MISS
  rc2, out2 = run()
  assert rc2 == 0 and "hi world!" in out2, out2
  assert "not found" not in out2, out2  # warm cache -> HIT (no rebuild)
  # the binary lives under exactly one cksum dir -- the content-hash is stable across runs
  bins = list(cache.glob("*/greeter"))
  assert len(bins) == 1, [str(b) for b in bins]
