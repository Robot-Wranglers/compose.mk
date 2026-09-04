"""Unit coverage for the CORE `jqlang` kind (compose.mk's `__hosted__` partition)
-- specifically the features .cmk/gitops.cmk relies on after its jq cleanup:

  gitops.stat.branch -> `.locals()` + jq coercion (`tonumber`, a derived bool,
                        `split("\\t")` + `tonumber? // 0`).
  gitops.stat        -> composition: a shape that `fromjson`s captured JSON.
  gitops.stat.hooks  -> the stream base call `NAME(<jq flags>)` with `-R -n` +
                        `inputs` (fold raw stdin lines into an object).

Each snippet uses the core `jqlang` directly (no local re-definition) via the
`target_locals` pragma, run headless.  Docker-free (needs jq + git-free).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
# `dsl` comes from the `cmk` prelude (`from cmk import dsl`); the `jqlang` sub-language kind is
# used qualified as `dsl.jqlang` (dsl is not an openable module).
PRAGMA = "# cmk_pragma ::: { \"target_locals\": true } :::\nfrom cmk import dsl\n"


def _run(tmp_path, body):
  f = tmp_path / "gj.cmk"
  f.write_text("#!/usr/bin/env -S ./compose.mk cmk run\n" + PRAGMA + body)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return p


def test_locals_coerce_number_and_bool(tmp_path):
  # gitops.stat.branch shape: `__locals__` strings -> numbers (tonumber) and a
  # derived bool (count > 0).
  p = _run(
    tmp_path,
    "dsl.jqlang shape(| { n: (.count | tonumber), dirty: ((.count | tonumber) > 0) } |)\n"
    "demo:\n\tcount <- echo 3\n\tshape.locals()\n__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"n": 3' in p.stdout and '"dirty": true' in p.stdout


def test_locals_split_and_optional_default(tmp_path):
  # the upstream ahead/behind trick: split a tab-joined value, coerce each with
  # `tonumber? // 0` so a missing/empty field defaults to 0.
  p = _run(
    tmp_path,
    "dsl.jqlang up(| { a: ((.ab | split(\"\\t\")[0] | tonumber?) // 0),"
    " b: ((.ab | split(\"\\t\")[1] | tonumber?) // 0) } |)\n"
    "demo:\n\tab <- printf '5\\t9'\n\tup.locals()\n__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a": 5' in p.stdout and '"b": 9' in p.stdout


def test_locals_split_empty_defaults_zero(tmp_path):
  # when the tab value is empty (no upstream), both fields default to 0.
  p = _run(
    tmp_path,
    "dsl.jqlang up(| { a: ((.ab | split(\"\\t\")[0] | tonumber?) // 0),"
    " b: ((.ab | split(\"\\t\")[1] | tonumber?) // 0) } |)\n"
    "demo:\n\tab <- printf ''\n\tup.locals()\n__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a": 0' in p.stdout and '"b": 0' in p.stdout


def test_compose_via_fromjson(tmp_path):
  # gitops.stat: a parent shape merges a captured JSON string via `fromjson`.
  p = _run(
    tmp_path,
    "dsl.jqlang top(| (.s | fromjson) + { extra: true } |)\n"
    "demo:\n\ts <- printf '{\"a\":1}'\n\ttop.locals()\n__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a": 1' in p.stdout and '"extra": true' in p.stdout


def test_stream_base_call_with_raw_null_flags(tmp_path):
  # gitops.stat.hooks: the base call `NAME(-R -n)` folds raw stdin lines
  # (via `inputs`) into an object.
  p = _run(
    tmp_path,
    "dsl.jqlang fold(| [inputs | select(length > 0) | split(\" \")"
    " | { key: .[0], value: .[1] }] | from_entries |)\n"
    "demo:\n\tprintf 'a 1\\nb 2\\n' | fold(-R -n)\n__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a": "1"' in p.stdout and '"b": "2"' in p.stdout
