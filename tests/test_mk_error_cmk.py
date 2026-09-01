"""Contract for the errno table + root error emitters (stage 2+3).

  * mk.errno       -- an m5.table: curated symbol -> exit code (resolve/default).
  * mk.error       -- expansion-time root emitter (thin $(error) wrapper); stamps
                      the curated code for supervisor fidelity, aborts with a
                      parseable `cmk-fault errno=.. code=.. :: msg :: meta` payload.
  * mk.die         -- recipe-time twin; themed line + exact exit via mk.super.status.
  * assert.env.var -- dogfood: routes through mk.die (no inline fault switch).

Core-only (no fault module): the emitters EMIT, they do not throw.  These run
under the supervisor (via `cmk run`), so the curated code reaches the OS.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "e.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def test_errno_resolve(tmp_path):
  # forward accessor + resolve (hit / unknown-default).
  r, out = _run(
    "__main__:\n"
    "\t@printf 'a=%s b=%s c=%s\\n' "
    "'$(call mk.errno.resolve,ENVVAR_UNSET)' "
    "'$(call mk.errno.resolve,NOPE)' '$(mk.errno[MODULE_MISSING])'\n",
    tmp_path)
  assert r.returncode == 0, out
  assert "a=39 b=1 c=66" in out, out


def test_mk_error_emits_parseable_schema(tmp_path):
  # expansion-time $(error): aborts, carrying errno/code/msg/meta.
  r, out = _run(
    "__main__:; $(call mk.error, boom, errno=MODULE_MISSING, ctx=foo)\n", tmp_path)
  assert r.returncode != 0, out
  assert "cmk-fault errno=MODULE_MISSING code=66" in out, out
  assert ":: boom" in out, out
  assert "ctx=foo" in out, out


@pytest.mark.supervisor
def test_mk_die_exits_mapped_code(tmp_path):
  # recipe-time: the curated code (39) surfaces via the supervisor.
  r, out = _run("__main__:; $(call mk.die, boom, errno=ENVVAR_UNSET)\n", tmp_path)
  assert r.returncode == 39, out


@pytest.mark.supervisor
def test_assert_env_var_routes_through_mk_die(tmp_path):
  # dogfood: unset var -> the themed message + exit 39, no fault module present.
  r, out = _run("__main__:; $(call assert.env.var, DEFINITELY_UNSET_XYZ)\n", tmp_path)
  assert r.returncode == 39, out
  assert "required variable" in out and "unset" in out, out


@pytest.mark.supervisor
def test_compile_time_errno_surfaces_exit_code(tmp_path):
  # An EXPANSION-time mk.error (an $(error), not a recipe exit) still surfaces its
  # curated errno as the OS exit code: mk.validate records code=N from the
  # classified schema into the supervisor pidfile, and the interpret failure
  # handler defers to it rather than clobbering with make's flattened 2.
  r, out = _run("__main__:; $(call mk.error, boom, errno=MODULE_MISSING)\n", tmp_path)
  assert r.returncode == 66, out
