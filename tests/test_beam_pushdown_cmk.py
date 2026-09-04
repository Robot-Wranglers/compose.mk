"""Executable spec for the fluxpush compiler stage (not yet built).

Per the pushdown spike doc: a plugin-lifted `compiler_post` stage, active
under the portal pragma, lowers declarative flux spellings (prereqs and
callforms) to the delegated `flux.push` form and leaves imperative and
shell-argument spellings untouched. Strict xfails are the contract; the
plain tests are invariants that must hold before and after the stage lands.
"""

from pathlib import Path

import pytest

pytestmark = [pytest.mark.experimental]

REPO = Path(__file__).resolve().parent.parent

_PROBE = (
  "#!/usr/bin/env -S ./compose.mk cmk run\n"
  "# cmk_pragma ::: { \"compiler_post\": \"fluxpush\" } :::\n"
  "import flux\n"
  "a:; echo A\n"
  "b:; echo B\n"
  "seq: flux.and/a,b\n"
  "race: flux.any/a,b\n"
  "body:\n"
  "  cmk.flux.mux(a, b)\n"
  "local:\n"
  "  ${make} flux.or/a,b\n"
  "shellarg:\n"
  "  cmk.flux.retry(echo hi, 2)\n"
  "__main__: seq\n"
)

_XFAIL = pytest.mark.xfail(
  reason="fluxpush compiler stage not yet built (see the pushdown spike doc)",
  strict=True,
)


def _compile(cmk, name, src):
  probe = REPO / name
  try:
    probe.write_text(src)
    r = cmk("cmk", "compile", name, cwd=REPO, timeout=300,
            env={"CMK_INTERNAL": "0", "CMK_SUPERVISOR": "1"})
    assert r.ok, f"compile failed\n{(r.stdout + r.stderr)[-2000:]}"
    return r.stdout
  finally:
    probe.unlink(missing_ok=True)


@_XFAIL
def test_prereq_spelling_lowers_to_delegated_form(cmk):
  twin = _compile(cmk, ".tmp.fluxpush.probe.cmk", _PROBE)
  assert "flux.push/and,a,b" in twin, "prereq head not delegated"
  assert "flux.push/any,a,b" in twin, "prereq head not delegated"


@_XFAIL
def test_callform_spelling_lowers_to_delegated_form(cmk):
  twin = _compile(cmk, ".tmp.fluxpush.probe.cmk", _PROBE)
  assert "$(call flux.push,mux" in twin, "callform not delegated"
  assert "$(call flux.mux" not in twin, "original callform lowering remains"


@_XFAIL
def test_stage_rides_module_staging(cmk):
  mod = REPO / ".tmp.fluxpushmod.cmk"
  main = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "# cmk_pragma ::: { \"compiler_post\": \"fluxpush\" } :::\n"
    "import flux\n"
    "from .tmp.fluxpushmod import mseq\n"
    "__main__: mseq\n"
  )
  try:
    mod.write_text(
      "#!/usr/bin/env -S ./compose.mk cmk compile\n"
      "import flux\n"
      "ma:; echo MA\n"
      "mseq: flux.and/ma,ma\n"
    )
    _compile(cmk, ".tmp.fluxpush.main.cmk", main)
    staged = sorted(REPO.glob(".cmk/.tmp.module..tmp.fluxpushmod-*.mk"))
    assert staged, "module was not staged"
    body = staged[-1].read_text()
    assert "flux.push/and,ma,ma" in body, "staged module prereq not delegated"
  finally:
    mod.unlink(missing_ok=True)


def test_imperative_spelling_stays_local(cmk):
  twin = _compile(cmk, ".tmp.fluxpush.probe.cmk", _PROBE)
  assert "flux.or/a,b" in twin, "imperative shell spelling must stay verbatim"
  assert "flux.push/or" not in twin, "imperative spelling must not be delegated"


def test_shell_argument_callform_stays_native(cmk):
  twin = _compile(cmk, ".tmp.fluxpush.probe.cmk", _PROBE)
  assert "flux.retry" in twin, "shell-argument combinator missing"
  assert "flux.push,retry" not in twin, "shell-argument combinator must stay native"
