"""Regression guard for beam-tramp's TRANSFER/initial-goal target-rewrite (rewrite_targets/1).

Beam-tramp must apply `.awk.rewrite.targets.maybe` like the bash supervisor does at
compose.mk:48 (initial goal) and :6632 (every TRANSFER): a BARE target goal is wrapped
with ``flux.pre/X X flux.post/X`` (the per-make-level VM ledger + user flux hooks),
while slash-/dot- goals pass through unchanged.

The bash-VM tests (test_vm*, test_backtracking, ...) never exercise this -- they run
under the *bash* tramp -- so a beam-tramp divergence here is invisible to them (it was:
beam-tramp ran bare targets RAW until the fix).  This pins it directly on beam-tramp.

CRUCIAL: the goal must be DIRECT-DRIVEN on the resident loop (CMK_TRAMP_MK=<compiled
program>).  A `cmk run <prog>` ip would run the program under BASH-tramp (which does its
own rewrite) and would pass even if rewrite_targets/1 were deleted from beam-tramp.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skip(reason="beam tramp / platform.beam is in-flight WIP, not certified")

REPO = Path(__file__).resolve().parent.parent
BEAM_IMG = "compose.mk:beam.node"

# a probe: flux.pre/post echo markers (so the wrapping is observable), a BARE target, and
# a SLASH target (which must pass through the rewrite unwrapped).
_PROBE = (
  "#!/usr/bin/env -S ./compose.mk cmk run\n"
  "flux.pre/%:; @printf 'FLUXPRE:%s\\n' \"${*}\" >&2\n"
  "flux.post/%:; @printf 'FLUXPOST:%s\\n' \"${*}\" >&2\n"
  "demotgt:; @echo IN-DEMOTGT\n"
  "find/%:; @echo FOUND-${*}\n"
)

# a one-line driver that loads platform.beam and builds the beam.node image (idempotent).
_BUILD = (
  "#!/usr/bin/env -S ./compose.mk cmk run\n"
  "import platform.beam.cmk flat=1\n"
  "__main__:; ${make} beam.node.build\n"
)

# in ONE container: compile the probe, then direct-drive a BARE and a SLASH goal through
# beam-tramp (each `2>&1` so the loop's routed stderr interleaves in order under a marker).
_SCRIPT = (
  "./compose.mk cmk compile .tmp.beamflux.probe.cmk > .tmp.beamflux.mk 2>/dev/null && "
  "MK='make -sS --no-print-directory -f .tmp.beamflux.mk' && "
  "echo '===BARE==='; CMK_PLUGINS_DIR=.cmk CMK_TRAMP_MK=\"$MK\" elixir .cmk/beam-tramp.exs demotgt 2>&1; "
  "echo '===SLASH==='; CMK_PLUGINS_DIR=.cmk CMK_TRAMP_MK=\"$MK\" elixir .cmk/beam-tramp.exs find/5 2>&1"
)


@pytest.mark.integration
@pytest.mark.needs_docker
def test_beam_tramp_rewrites_bare_but_not_slash(cmk):
  builder = REPO / ".tmp.beamflux.build.cmk"
  probe = REPO / ".tmp.beamflux.probe.cmk"
  try:
    builder.write_text(_BUILD)
    bd = cmk("cmk", "run", ".tmp.beamflux.build.cmk", cwd=REPO,
             env={"CMK_SUPERVISOR": "1"}, timeout=600)
    assert bd.ok, f"beam.node.build failed\n{bd.stderr[-1500:]}"

    probe.write_text(_PROBE)
    r = subprocess.run(
      ["docker", "run", "--rm", "-v", f"{REPO}:/workspace", "-w", "/workspace",
       BEAM_IMG, "bash", "-c", _SCRIPT],
      cwd=str(REPO), capture_output=True, text=True, timeout=300,
    )
    out = r.stdout or (r.stdout + r.stderr)
    bare, _, slash = out.partition("===SLASH===")

    # BARE target -> rewrite wraps it -> flux.pre/post fire around the target.
    assert "IN-DEMOTGT" in bare, f"bare target didn't run\n{out[-2000:]}"
    assert "FLUXPRE:demotgt" in bare, f"flux.pre not fired -- bare-target rewrite missing?\n{out[-2000:]}"
    assert "FLUXPOST:demotgt" in bare, f"flux.post not fired -- bare-target rewrite missing?\n{out[-2000:]}"

    # SLASH target -> passthrough -> NO flux wrapping.
    assert "FOUND-5" in slash, f"slash target didn't run\n{out[-2000:]}"
    assert "FLUXPRE" not in slash, f"slash target must NOT be wrapped with flux.pre\n{out[-2000:]}"
  finally:
    builder.unlink(missing_ok=True)
    probe.unlink(missing_ok=True)
    (REPO / ".tmp.beamflux.mk").unlink(missing_ok=True)
