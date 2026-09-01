"""Behavioral tests for the external `fault.cmk` module (typed exceptions).

The `plugin` suite (test_plugins.py) only smoke-tests that every `.cmk/` plugin imports and
exposes its public surface.  This suite goes further for fault.cmk -- it exercises the actual
runtime: a thrown fault routes to a `fault/<Type>:` handler by make precedence (no registry),
an explicit handler beats the `fault/%:` fallback, `fault.guarded` bridges a raw subprocess
failure into a typed SubprocessFault, and loading the module upgrades core's `assert.env.var`
in place (a failed assertion raises a typed EnvVarUnset instead of a bare `exit 39`).

fault.cmk lives in the external `.cmk` submodule and owns the `fault.` namespace (module-like),
so these are the first "external-module" *behavioral* tests -- distinct from the import-level
`plugin` suite.  See the follow-up on organizing dedicated external-modules / external-plugins
suites.

The structured emit runs `jb` (a docker coprocess), so routing needs a daemon -> needs_docker.
"""
import os
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
CMK_DIR = REPO / ".cmk"

pytestmark = [pytest.mark.external_module, pytest.mark.integration, pytest.mark.needs_docker, pytest.mark.module_system]


def _run(tmp_path, body, *targets, timeout=180):
  """Load fault.cmk into a synthetic plain Makefile and run `targets`.

  Mirrors test_plugins.py: the plugin is found in the real `.cmk` (CMK_PLUGINS_DIR) but staged
  into tmp_path (CMK_MODULES_DIR), so the submodule stays clean.  A plain `make -f` has no
  compose.mk supervisor, so there is no automatic at-exit drain -- faults are thrown in a
  swallowed sub-make (`|| true`), kept in flight, and drained explicitly (`fault.dispatch.by_type`).
  """
  mk = tmp_path / "prog.mk"
  mk.write_text("include {}\n$(call include.plugins, fault.cmk)\n".format(COMPOSE) + body)
  env = {
    **os.environ,
    "CMK_PLUGINS_DIR": str(CMK_DIR),
    "CMK_MODULES_DIR": str(tmp_path),
    "NO_COLOR": "1",
  }
  return subprocess.run(
    ["make", "-f", str(mk), *targets],
    cwd=str(tmp_path), capture_output=True, text=True, errors="replace", env=env, timeout=timeout,
  )


def test_throw_fails_the_recipe(tmp_path):
  # unswallowed raise: a throw fails the recipe, it does not merely log.  The only pin on that.
  r = _run(tmp_path, "boom:; $(call fault.throw,MyFault)\n", "boom")
  txt = r.stdout + r.stderr
  assert r.returncode != 0, txt
  assert "MyFault" in txt, txt


# swallow-then-drain wrapper: throw in an isolated sub-make, keep the event in flight, drain it.
_DRAIN = "run:\n\t@${make} boom </dev/null || true\n\t@${make} fault.dispatch.by_type\n"


def test_throw_routes_to_typed_handler(tmp_path):
  # fault.throw emits a typed event and fails; at the drain it routes to `fault/<Type>:` --
  # routing is just make rule precedence, no handler registry to maintain.
  r = _run(tmp_path,
           "fault/MyFault:; @echo HANDLED-MyFault\n"
           "boom:; $(call fault.throw,MyFault)\n" + _DRAIN,
           "run")
  assert r.returncode == 0, r.stderr
  assert "HANDLED-MyFault" in r.stdout + r.stderr


def test_specific_handler_beats_fallback(tmp_path):
  # An explicit `fault/<Type>:` wins over the module's `fault/%:` fallback (rule precedence).
  r = _run(tmp_path,
           "fault/Specific:; @echo SPECIFIC-RAN\n"
           "boom:; $(call fault.throw,Specific)\n" + _DRAIN,
           "run")
  txt = r.stdout + r.stderr
  assert "SPECIFIC-RAN" in txt, txt
  assert "no handler registered" not in txt  # the fault/%: fallback message


def test_guarded_bridges_subprocess_failure(tmp_path):
  # fault.guarded catches a raw nonzero exit and re-throws a typed SubprocessFault, drained to
  # the module's built-in `fault/SubprocessFault:` handler.
  r = _run(tmp_path,
           "boom:; sh -c 'exit 3' || { $(fault.guarded) }\n" + _DRAIN,
           "run")
  assert "SubprocessFault" in r.stdout + r.stderr, r.stderr


def test_assert_env_var_upgrades_when_module_loaded(tmp_path):
  # Core's assert.env.var degrade-switch: with fault.cmk loaded, a failed assertion raises a
  # typed EnvVarUnset fault (routes to a handler) instead of a bare `exit 39`.
  r = _run(tmp_path,
           "fault/EnvVarUnset:; @echo UPGRADED-EnvVarUnset\n"
           "boom:; $(call assert.env.var,DEFINITELY_UNSET_VAR_XYZ)\n" + _DRAIN,
           "run")
  assert "UPGRADED-EnvVarUnset" in r.stdout + r.stderr, r.stderr


def test_classify_maps_errno_to_type_when_module_loaded(tmp_path):
  # Dispatch unification: with fault.cmk loaded, the classifier maps a carried
  # errno symbol to its fault Type, so expansion-time faults (via mk.super.fault /
  # mk.validate) route to fault/<Type> consistently with the runtime mk.die path.
  # A foreign make error passes through unmapped.
  r = _run(tmp_path,
           "cl:; @printf 'cmk-fault errno=MODULE_MISSING code=66 :: boom\\n' | ${lang.runtime.classify_fault}\n"
           "clr:; @printf 'No rule to make target foo\\n' | ${lang.runtime.classify_fault}\n",
           "cl", "clr")
  out = r.stdout + r.stderr
  assert "ModuleNotFound" in out, out
  assert "RuleMissing" in out, out
