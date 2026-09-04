"""Reflective-tower Phase 1 (payoff #7): a compile stage's export IS a fragment-render operation.

The compiler's awk-pass composer exports each stage as `_awklang_<name> := lang.grammar.ctx.fill(
splice(sources))`.  `lang.grammar.ctx.fill` is the fixed grammar-hole fill (`@@SYM_NAME@@`/
`@@BANANA_OPEN_*@@`/...), and it is the SAME `m5.quasi%` primitive the fragment Templatable
surface (`.render`/`.__mod__`) is built from.  So a compile stage can be a `lang.banana.fragment` whose
`.__mod__` is `inject` -- the "sym.inject becomes __mod__" step from the plan.

This pins the provable kernel for a MAIN-ONLY leaf stage: `inject($(value .awk.cmk.<stage>)$(nl))`
reproduces the current `_awklang_<stage>` export BYTE-FOR-BYTE.  Note the grammar values are regexes with
spaces/brackets, so they cannot ride the generic `render(k=v)` kwarg path -- which is exactly why the
stage-fragment `.__mod__` must be `inject`, not generic render.  This guards the export ==
fragment-render equivalence a rebase relies on.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# (stage-block-suffix, exported name) -- both are MAIN-ONLY registrations (no pipeline=),
# so the export is exactly inject(splice(main)) with a single source.
LEAF_STAGES = [
  ("cmkanchor", "cmkanchor"),
  ("unsentinel", "unsentinel"),
]


@pytest.mark.parametrize("stage,export", LEAF_STAGES)
def test_stage_export_is_fragment_render(tmp_path, stage, export):
  repro = tmp_path / "repro.awk"
  cur = tmp_path / "cur.awk"
  f = tmp_path / "probe.cmk"
  f.write_text(
    f"$(file >{repro},$(call lang.grammar.ctx.fill,$(value .awk.cmk.{stage})$(nl)))\n"
    f"$(file >{cur},$(value _awklang_{export}))\n"
    "probe:; @true\n"
  )
  subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "probe"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=120,
  )
  assert repro.exists() and cur.exists(), "probe did not materialize both outputs"
  assert repro.read_bytes() == cur.read_bytes(), (
    f"stage {stage}: inject(source) diverged from the compiler export _awklang_{export} "
    f"-- the fragment-render equivalence the #7 rebase relies on is broken"
  )


# Phase 2: a MULTI-source stage (main + pipeline=deps) is reproduced by the fragment ALGEBRA --
# `.__concat__` (== `m5.splice!` of the reversed pipeline + main) then `.__mod__` (== inject).
# (main-stem, pipeline-deps, export-name); mirrors `lang.awk.export`'s `m5.lex.rev` ordering exactly.
MULTI_STAGES = [
  ("dedent", ["errors", "banana"], "dedent"),
]


@pytest.mark.parametrize("stage,pipeline,export", MULTI_STAGES)
def test_multisource_stage_is_fragment_algebra(tmp_path, stage, pipeline, export):
  repro = tmp_path / "repro.awk"
  cur = tmp_path / "cur.awk"
  pipe = " ".join(f".awk.cmk.{p}" for p in pipeline)
  f = tmp_path / "probe.cmk"
  f.write_text(
    f"_ordered := $(call m5.lex.rev,{pipe}) .awk.cmk.{stage}\n"
    f"$(file >{repro},$(call lang.grammar.ctx.fill,$(call m5.splice!,$(_ordered))))\n"
    f"$(file >{cur},$(value _awklang_{export}))\n"
    "probe:; @true\n"
  )
  subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "probe"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=120,
  )
  assert repro.exists() and cur.exists(), "probe did not materialize both outputs"
  assert repro.read_bytes() == cur.read_bytes(), (
    f"multi-source stage {stage}: frag-algebra (concat+mod) diverged from _awklang_{export}"
  )


# Phase 3 (design proof, still no live-pipeline edit): the stage-fragment KIND itself.  A seed minter
# (like _lang.banana.fragment) whose `.__mod__` is `lang.grammar.ctx.fill` applied to the source+newline
# (splice semantics for one source).  Making a real compile stage an INSTANCE and materializing it via
# its own `.__mod__` reproduces the compiler export -- proving the kind design before it is WIRED.
def test_stage_fragment_kind_reproduces_export(tmp_path):
  frag = tmp_path / "frag.awk"
  cur = tmp_path / "cur.awk"
  f = tmp_path / "probe.cmk"
  f.write_text(
    "$(call m5.def.!, proto.stage.frag, _proto.stage.frag)\n"
    "define _proto.stage.frag\n"
    "$(eval _sf := $(or $(call mk.kwargs.get,${1},def),$(firstword ${1})))\n"
    "$$(call lang.seed.materialize!, $(_sf), lang.proto.tmpl.materializable)\n"
    "$(_sf).__mod__ = $$(call lang.grammar.ctx.fill,$$(value $(_sf).shape)$${nl})\n"
    "endef\n"
    "$(eval $(call proto.stage.frag, def=.awk.cmk.cmkanchor))\n"
    f"$(file >{frag},$(.awk.cmk.cmkanchor.__mod__))\n"
    f"$(file >{cur},$(value _awklang_cmkanchor))\n"
    "probe:; @true\n"
  )
  subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "probe"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    timeout=120,
  )
  assert frag.exists() and cur.exists(), "probe did not materialize both outputs"
  assert frag.read_bytes() == cur.read_bytes(), (
    "stage-fragment instance .__mod__ diverged from the compiler export -- the kind design is broken"
  )
