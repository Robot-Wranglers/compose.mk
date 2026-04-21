"""`.PHONY` collision guard: client files/dirs that shadow compose.mk targets.

Background: compose.mk runs under `-s` (compose.mk:73). GNU make treats a
recipe-bearing, no-prerequisite target as "up to date" whenever a file OR
directory of that name exists, so without `.PHONY` a client project that has a
`help/` dir (or a `cmk` helper script, etc.) silently turns the matching
compose.mk target into a no-op -- and `-s` suppresses even the "up to date"
line, so the shadowed target looks like a clean exit-0 success.

The fix (route 2b): the remade `__hosted__` cache appends a generated `.PHONY:`
manifest listing the BARE (dotless) core targets -- the exact set a client file/dir
can forward-shadow (`help`, `mkparse`, `cmk`, `yq`, ...). It rides the existing warm
`-include`, so it costs nothing at parse time.

Scope, by design:
  * BARE core targets ARE guarded: `help`, `cmk`, `mkparse`, ... A client file/dir
    of that name no longer shadows the target.
  * NAMESPACE-ONLY roots (`io`, `flux`, `comp` -- core ships `io.foo` but no bare
    `io:`) are intentionally NOT phony'd: they protect nothing on our side and would
    wrongly force a client's real same-named target to always rebuild (the reverse
    collision). See `test_manifest_excludes_namespace_only_roots`.
  * dotted LEAVES (`flux.ok`, `io.bash`) are intentionally OUT of scope -- a file
    named literally `flux.ok` is implausible, and covering every leaf would bloat
    `.PHONY` to ~400 names. See `test_dotted_leaf_out_of_scope`.

`_cmk.phony.bare` (compose.mk) is the source of the manifest; this module's
`_source_bare` recomputes the same set so `test_manifest_covers_all_bare_targets`
fails loudly if a newly-added bare target ever drifts out of the shipped manifest.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"

# Namespace roots that are also BARE (dotless) public targets -- the real,
# high-value collision surface. Each runs a recipe and prints a stable marker.
BARE_TARGETS = [
  pytest.param("help", "cli.cmk", id="help"),
  pytest.param("mkparse", "flux", id="mkparse"),
]


def _ran(result, marker):
  """True if the target's recipe actually fired (marker present, clean exit)."""
  return result.returncode == 0 and marker in (result.stdout + result.stderr)


# --- the guard works: a same-named file/dir no longer shadows a root target ---


@pytest.mark.parametrize("as_dir", [False, True], ids=["file", "dir"])
@pytest.mark.parametrize("target,marker", BARE_TARGETS)
def test_tool_mode_root_survives_collision(cmk, tmp_path, target, marker, as_dir):
  # Tool/global mode: `./compose.mk <target>` with a colliding file/dir in cwd.
  victim = tmp_path / target
  victim.mkdir() if as_dir else victim.write_text("")
  r = cmk(target, cwd=tmp_path)
  assert _ran(r, marker), (
    f"{target} shadowed by a {'dir' if as_dir else 'file'} named {target!r} "
    f"(exit={r.returncode}, empty output == silent no-op)"
  )


@pytest.mark.parametrize("as_dir", [False, True], ids=["file", "dir"])
@pytest.mark.parametrize("target,marker", BARE_TARGETS)
def test_local_mode_root_survives_collision(cmk, tmp_path, target, marker, as_dir):
  # Local/include mode: a client Makefile that `include`s compose.mk.
  (tmp_path / "Makefile").write_text(f"include {COMPOSE_MK}\n")
  victim = tmp_path / target
  victim.mkdir() if as_dir else victim.write_text("")
  r = cmk(target, makefile=str(tmp_path / "Makefile"), cwd=tmp_path)
  assert _ran(r, marker), (
    f"{target} (include mode) shadowed by a {'dir' if as_dir else 'file'} named "
    f"{target!r} (exit={r.returncode}, empty output == silent no-op)"
  )


def test_namespace_root_dir_is_inert(cmk, tmp_path):
  # The user's original scenario: a subdir named after an internal namespace.
  # There is no bare `docker`/`flux` target to shadow, and the roots are phony
  # anyway, so a `docker/` subdir cannot interfere with `flux.ok`.
  (tmp_path / "docker").mkdir()
  (tmp_path / "flux").mkdir()
  r = cmk("flux.ok", cwd=tmp_path)
  assert _ran(r, "succeeding"), f"flux.ok disturbed by docker//flux/ dirs: {r.stderr}"


# --- documented boundary: dotted leaves are intentionally NOT guarded ---------


def test_dotted_leaf_out_of_scope(cmk, tmp_path):
  # A file named exactly `flux.ok` still shadows the leaf target -- accepted, the
  # manifest guards roots not leaves. If this ever starts *running* (leaves got
  # covered), revisit the scope note above.
  (tmp_path / "flux.ok").write_text("")
  r = cmk("flux.ok", cwd=tmp_path)
  assert not _ran(r, "succeeding"), (
    "flux.ok ran despite an exact-name file collision -- leaves now covered? "
    "update the scope note and BARE_TARGETS."
  )


# --- the shipped manifest stays complete as roots are added -------------------


def _source_heads():
  """Every real rule head from compose.mk (seed with `define` bodies stripped, plus
  the `__hosted__` region whose heads lower to real targets), minus `X:=` assignments
  and embedded-YAML define bodies -- the shared input for `_cmk.phony.roots`/`.bare`."""
  txt = COMPOSE_MK.read_text().splitlines()
  seed, out, in_def, in_hosted = [], [], False, []
  for ln in txt:
    if ln.startswith("define "):
      in_def = True
      in_hosted = ln.startswith("define __hosted__")
      continue
    if ln.startswith("endef"):
      in_def = in_hosted = False
      continue
    if in_hosted:
      out.append(ln)
    if not in_def:
      seed.append(ln)
  head = re.compile(r"^[A-Za-z_][A-Za-z0-9._/%-]*:(?!=)")
  return [ln.split(":", 1)[0] for ln in seed + out if head.match(ln)]


def _source_roots():
  """Mirror `_cmk.phony.roots`: first-segment of every head (the namespace list)."""
  return {re.split(r"[./%]", h, 1)[0] for h in _source_heads()}


def _source_bare():
  """Mirror `_cmk.phony.bare`: only heads that are themselves bare (dotless) targets
  -- the set the `.PHONY` manifest ships. Namespace-only roots (`io`, `flux`) and
  parametric heads (`foo/%`) are excluded."""
  return {h for h in _source_heads() if not re.search(r"[./%]", h)}


def _built_manifest(tmp_path):
  """Build the hosted cache into an isolated dir and return its .PHONY set."""
  env = {"HOSTED_CACHE_DIR": str(tmp_path), "NO_COLOR": "1"}
  subprocess.run(
    [str(COMPOSE_MK), "flux.ok"],
    cwd=str(tmp_path),
    env={**__import__("os").environ, **env},
    capture_output=True,
    text=True,
  )
  caches = list(tmp_path.glob(".tmp.hosted.*.mk"))
  assert caches, "hosted cache was not built"
  for line in caches[0].read_text().splitlines():
    if line.startswith(".PHONY:"):
      return set(line[len(".PHONY:"):].split())
  return set()


def test_manifest_covers_all_bare_targets(tmp_path):
  # The manifest must guard every bare (dotless) core target -- the real
  # forward-shadow surface. Recomputed from source so a newly-added bare target that
  # drifts out of the shipped manifest fails loudly.
  manifest = _built_manifest(tmp_path)
  missing = _source_bare() - manifest
  assert not missing, (
    f"bare core targets missing from the shipped .PHONY manifest: {sorted(missing)} "
    f"-- regenerate the hosted cache or check _cmk.phony.bare in compose.mk"
  )


def test_manifest_excludes_namespace_only_roots(tmp_path):
  # The reverse-collision fix: namespace-only roots (core has `io.foo`/`flux.foo` but
  # no bare `io:`/`flux:`) must NOT be phony'd -- else a client's real same-named
  # file-target gets wrongly forced always-rebuild. Only bare heads belong here.
  manifest = _built_manifest(tmp_path)
  namespace_only = (_source_roots() - _source_bare()) & manifest
  assert not namespace_only, (
    f"namespace-only roots wrongly marked .PHONY: {sorted(namespace_only)} -- these "
    f"have no bare core target and would shadow a client's real same-named target"
  )


def test_manifest_excludes_embedded_yaml_and_assignments(tmp_path):
  # `services`/`volumes` (embedded compose YAML) and `SHELL`/`MAKEFLAGS`
  # (assignments) must NOT be phony -- a client's real `services/` dir would break.
  manifest = _built_manifest(tmp_path)
  junk = {"services", "volumes", "windows", "options", "SHELL", "MAKEFLAGS"}
  leaked = junk & manifest
  assert not leaked, f"non-target names wrongly marked .PHONY: {sorted(leaked)}"
