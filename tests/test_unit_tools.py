"""Unit tests for the `tools` module (jq/yq/jb/glow) and its flat projection.

The four third-party CLI helpers are authored once under `tools.*` and projected
onto the bare `jq`/`yq`/`jb`/`glow` names by `lang.module.bind` -- the same
flat-bind `import tools flat=1` runs.  These tests pin:

  * the flat projection (a future `tools.__all__` reshuffle can't silently drop a
    bare handle, and `tools.X` must stay byte-identical to the projected `X`),
  * the module's auto-minted reflection (`__all__` / `__dir__` / registry).
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _get(cmk, var):
  r = cmk(f"mk.get/{var}")
  assert r.ok, r.stderr
  return r.stdout.strip()


def _wrapper(tmp_path, recipe, name="tw.mk"):
  w = tmp_path / name
  w.write_text(f"include {COMPOSE_MK}\nprobe:;{recipe}\n")
  return str(w)


# --- flat projection: tools.X == bare X, all nonempty --------------------------

# (module handle, flat-projected bare name) pairs that MUST stay identical.
FLAT_PAIRS = [
  ("tools.jq", "jq"),
  ("tools.jq.run", "jq.run"),
  ("tools.jq.docker", "jq.docker"),
  ("tools.jq.slurp.nonempty", "jq.slurp.nonempty"),
  ("tools.yq", "yq"),
  ("tools.yq.run", "yq.run"),
  ("tools.jb", "jb"),
  ("tools.jb.run", "jb.run"),
  ("tools.jb.docker", "jb.docker"),
  ("tools.jb.array", "jb.array"),
  ("tools.glow", "glow"),
  ("tools.glow.run", "glow.run"),
  ("tools.glow.docker", "glow.docker"),
]


@pytest.mark.parametrize("moduled,bare", FLAT_PAIRS)
def test_flat_projection_equal_and_nonempty(cmk, moduled, bare):
  m, b = _get(cmk, moduled), _get(cmk, bare)
  assert m == b, f"{moduled}={m!r} but {bare}={b!r} -- flat projection drifted"
  assert m, f"{moduled} resolved empty"


# --- module identity + reflection ---------------------------------------------


def test_tools_is_registered_module(cmk):
  # A namespace carrying `.__all__` IS a core module (lang.module.core).
  assert "tools" in _get(cmk, "lang.module.core").split()


def test_tools_all_manifest(cmk):
  assert _get(cmk, "tools.__all__").split() == ["jq", "yq", "jb", "glow"]


def test_tools_dir_reflects_members_and_subattrs(cmk):
  d = _get(cmk, "tools.__dir__").split()
  for m in ("jq", "yq", "jb", "glow"):
    assert m in d, f"member {m} missing from tools.__dir__"
  for sub in ("jq.run", "jb.docker", "glow.run", "jq.slurp.nonempty", "jb.array"):
    assert sub in d, f"sub-attr {sub} missing from tools.__dir__"


# --- functional (jq is on PATH in all CI/test envs) ---------------------------


def test_functional_jq_via_flat_name(cmk, tmp_path):
  mk = _wrapper(tmp_path, "@printf '{\"x\":2}\\n' | ${jq} -c .x")
  r = cmk("probe", makefile=mk)
  assert r.ok, r.stderr
  assert r.stdout.strip() == "2"


# --- back-compat aliases onto the flat-bound handles --------------------------


def test_json_aliases_resolve_to_jb(cmk):
  jb = _get(cmk, "jb")
  assert _get(cmk, "json.from") == jb
  assert _get(cmk, "io.json_builder") == jb


def test_jb_init_backcompat_dispatches_to_tools_init(cmk, tmp_path):
  # `jb.init` is kept as a thin alias -> `tools.init/jb` (assert via dry-run).
  w = tmp_path / "d.mk"
  w.write_text(f"include {COMPOSE_MK}\n")
  r = cmk("-n", "jb.init", makefile=str(w))
  assert "tools.init/jb" in (r.stdout + r.stderr), (r.stdout, r.stderr)
