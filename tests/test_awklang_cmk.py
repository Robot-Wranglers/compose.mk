"""`dsl.awklang` -- mint an awk stage/utility from a define, abstracting the lang.grammar.ctx.fill +
`_cmk_blk_*` export (+ optional stdin runner) boilerplate.  A `dsl.*` sub-language kind
(sibling of `dsl.jqlang`), used qualified: `dsl.awklang NAME(| .. |)`.

Two surfaces: the raw `$(call dsl.awklang, def=<block> [run=<tgt> stem=<var>] ..)` (works
in the seed/core; the namespace utilities use it) and the `dsl.awklang NAME(| body |)`
banana ctor (export-only).  Both ride `$(value)` + the env-var `awk "$${_cmk_blk_X}"`
shape, so awk `$0` survives untouched -- the collision that sank the earlier
`_mk.def.to.fd` attempt.  See TODO (awklang) + the plan.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler

REPO = Path(__file__).resolve().parent.parent


def _run(cmk, src, name):
  p = REPO / (".tmp.awklang_%s.cmk" % name)
  p.write_text(src)
  try:
    r = cmk("cmk", "run", p.name, cwd=REPO, timeout=90, env={"CMK_SUPERVISOR": "1"})
    return r.stdout + r.stderr
  finally:
    p.unlink(missing_ok=True)


def test_banana_mints_runnable_stage(cmk):
  # qualified `dsl.awklang NAME(| body |)` (always-on) lowers to `$(call dsl.awklang,
  # def=NAME)`, exporting a usable `_awklang_NAME`.  The banana body's awk `$0` must survive
  # the whole compiler -> awklang -> export -> shell -> awk chain (single `$`, not stripped).
  out = _run(
    cmk,
    "dsl.awklang upcase(|\n  { print toupper($0) }\n|)\n"
    "__main__:; @printf 'hi there\\n' | awk \"$${_awklang_upcase}\"\n",
    "banana",
  )
  assert "HI THERE" in out, out[-800:]


def test_awklang_kind_qualified(cmk):
  # `dsl.awklang NAME(..)` (qualified) mints an awk-export kind instance directly; `dsl` is not an
  # openable module, so no `open dsl` -- reference the kind qualified.
  out = _run(
    cmk,
    "from cmk import dsl\ndsl.awklang upcase(|\n  { print toupper($0) }\n|)\n"
    "__main__:; @printf 'hey\\n' | awk \"$${_awklang_upcase}\"\n",
    "qualawk",
  )
  assert "HEY" in out, out[-800:]


def test_raw_call_generates_run_target(cmk):
  # the raw `$(call dsl.awklang, def=<block> run=<tgt> stem=<var>)` form (as the namespace
  # utilities use) also mints a `<tgt>/%` stdin runner passing the stem as `-v <var>`.
  out = _run(
    cmk,
    "define .awk.myblk\n  { print \"[\" p \"] \" $0 }\nendef\n"
    "$(call dsl.awklang, def=.awk.myblk run=myrun stem=p)\n"
    "__main__:; @printf 'x\\n' | this.myrun/tag\n",
    "run",
  )
  assert "[tag] x" in out, out[-800:]
