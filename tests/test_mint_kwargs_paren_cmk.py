"""Regression + xfail coverage for two bugs found 2026-07-31 (see memory
`thunk-into-mint-tmpl-holes-bug`).

1. mint-`.__tmpl` body-with-holes: a `cmk.module`/`cmk.namespace` body carries a
   `${body1}` slot; the thunk!/into! consolidation routed the mint capture through a
   `$(call)` wrapper, which corrupted the fill and left `.shape` empty (banana-module
   bug). REGRESSION: the instance body must reach `.shape`.

2. leading-paren ctor kwargs can't hold a `$(VAR)` ref: the compiler's `NAME(kwargs)`
   paren-extractor excludes parens, so `container py(img=$(VAR) ..)(| |)` emits verbatim
   and never mints. The paren-SAFE workaround is body-kwargs `container py(| .. |)`.
   XFAIL pins the open limitation; the body-kwargs test guards the workaround.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "probe.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_module_body_reaches_instance(tmp_path):
  # A cmk.module body is a body-with-`${body1}`-holes; the mint must fill it so the
  # instance's `.shape` holds the declared body (not empty). Guards against the
  # thunk!/into! mint-`.__tmpl` wrapper regression.
  r, out = _run_cmk(
    "cmk.module tools[|\n"
    "  greet:; printf hi\n"
    "|]\n"
    "demo:; @printf 'shape=[%s]' \"$(value tools.shape)\"\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "undefined variable 'body1'" not in out, out
  assert re.search(r"shape=\[.*greet.*\]", out), out   # the body reached .shape


def test_container_body_kwargs_with_var_ref(tmp_path):
  # PAREN-SAFE form: a `$(VAR)` ref inside the banana body mints cleanly.
  r, out = _run_cmk(
    "from cmk import container\n"
    "export FOO ?= python:3.11-slim\n"
    "container py(| img=$(FOO) entrypoint=python |)\n"
    "demo:; @printf 'class=[%s] img=[%s]' \"$(py.__class__)\" \"$(py.img)\"\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "class=[cmk.container]" in out, out
  assert "img=[python:3.11-slim]" in out, out


@pytest.mark.xfail(
  reason="OPEN compiler limitation: a $(VAR) ref in a LEADING-paren ctor kwarg breaks "
  "the mint -- the `NAME(kwargs)` paren-extractor (.awk.sugarawk ~10721 and the "
  "using-trailer path) excludes parens, so the line emits verbatim and never mints. "
  "Body-kwargs `container py(| .. |)` is the paren-safe workaround. If this xpasses, the "
  "paren-extract stages learned balanced parens -- drop the marker.",
  strict=False,
)
def test_container_leading_paren_kwargs_with_var_ref(tmp_path):
  r, out = _run_cmk(
    "from cmk import container\n"
    "export FOO ?= python:3.11-slim\n"
    "container py(img=$(FOO) entrypoint=python)(| |)\n"
    "demo:; @printf 'class=[%s]' \"$(py.__class__)\"\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "class=[cmk.container]" in out, out
