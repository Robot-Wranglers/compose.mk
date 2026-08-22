"""Characterization / parity net for the code-object minter (`_code.unbound`).

This PINS the CURRENT observable contract of a code-object so the planned convergence (routing
`code.unbound` onto the class tower + retiring its hand-rolled surface -- TODO-seed-protos.md
step 6b) can be proven behavior-preserving.  These tests must pass BEFORE that rewrite and stay
green AFTER it; a deliberate contract change should show up here as a failing assert to update.

Scope: the data/construction contract (shape/ctor-src/mint), the bound-vs-unbound distinction
(`.__machine__`/`.__in__` -- a bound object is Runnable, an unbound one is content), the `.copy`
re-mint, and one materialization round-trip (`.to.file`).  The run/interpreter surface
(`.with.file/<tgt>`, `.run/<arg>`, `.preview`, the bare-run dispatch) is exercised by the demo
sweep (test_demos_cmk_lang.py, docker-gated) and by test_code_object_template_cmk.py -- not
re-pinned here, since driving nested make through an interpreted `cmk run` recipe is flaky.

Docker-free (make only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(cmk_src, tmp_path, goal="probe", cwd=None):
  f = tmp_path / "co.cmk"
  f.write_text(cmk_src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(cwd or REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return r.stdout + r.stderr


# One fixture object exercised by module-level `$(info)` probes (parse-time -> no recipe
# shell-quoting eats the body).  Covers unbound data, `.copy`, and a bound sibling.
DATA_PROBE = r"""
code.unbound greeting(| BODYMARK hello @@who@@ |)

define payload
run me
endef
$(call code.unbound, def=payload bind=host.local)

_x := $(call greeting.copy,greeting_dup)

$(info P_SHAPE=[$(value greeting.shape)])
$(info P_CTORSRC=[$(value greeting.__ctor_src__)])
$(info P_MINT=[$(greeting.__ctor__)])
$(info P_UNBOUND_MACHINE=[$(origin greeting.__machine__)])
$(info P_UNBOUND_RUN=[$(origin greeting.__in__)])
$(info P_COPY_SHAPE=[$(value greeting_dup.shape)])
$(info P_COPY_MINT=[$(greeting_dup.__ctor__)])
$(info P_BOUND_MACHINE=[$(value payload.__machine__)])
$(info P_BOUND_RUN_ORIGIN=[$(origin payload.__in__)])
$(info P_BOUND_RUN_DELEGATES=[$(findstring host.local.__in__,$(value payload.__in__))])

probe:; @true
"""


def test_data_contract_shape_ctorsrc_mint(tmp_path):
  out = _run(DATA_PROBE, tmp_path)
  assert "P_SHAPE=[BODYMARK hello @@who@@]" in out          # .shape is the raw body
  assert "P_CTORSRC=[BODYMARK hello @@who@@]" in out        # .__ctor_src__ holds the source
  assert "P_MINT=[code.unbound]" in out             # .__ctor__ = the $1-form minter (not a class)


def test_unbound_is_not_runnable(tmp_path):
  # An UNBOUND code-object is content: no `.__machine__`, no `.__in__` (not Runnable).
  out = _run(DATA_PROBE, tmp_path)
  assert "P_UNBOUND_MACHINE=[undefined]" in out
  assert "P_UNBOUND_RUN=[undefined]" in out


def test_copy_remints_independent_same_kind(tmp_path):
  # `.copy` re-mints a fresh object of the SAME kind, carrying the same body.
  out = _run(DATA_PROBE, tmp_path)
  assert "P_COPY_SHAPE=[BODYMARK hello @@who@@]" in out
  assert "P_COPY_MINT=[code.unbound]" in out


def test_bound_object_is_runnable_and_delegates(tmp_path):
  # A BOUND object carries `.__machine__` == the binding and a `.__in__` (Runnable).  For a MACHINE
  # binding the `.__in__` delegates to the machine's own `.__in__`, handing it the body BY NAME so the
  # feed discipline materializes it at recipe time -- the same seam `lang.dsl.machine.proxy` uses.
  # Passing the materialized text instead would cross a callform argument, where `m5[1]`'s strip
  # collapses its indentation (see scratch/polyglot-indent-transport.md).  A plain-target binding
  # keeps the `.with.file/<target>` seam.
  out = _run(DATA_PROBE, tmp_path)
  assert "P_BOUND_MACHINE=[host.local]" in out
  assert "P_BOUND_RUN_ORIGIN=[undefined]" not in out       # .__in__ IS defined when bound
  assert "P_BOUND_RUN_DELEGATES=[host.local.__in__]" in out


def test_to_file_materializes_body(tmp_path):
  # `.to.file` writes the body to a tempfile and echoes its path (materialization round-trip).
  src = r"""
code.unbound blob(| MATERIALIZED-CONTENT line2 |)
probe:
	@f=`${make} blob.to.file 2>/dev/null | tail -1` && cat "$$f"
"""
  out = _run(src, tmp_path, cwd=tmp_path)
  assert "MATERIALIZED-CONTENT" in out


def test_fd_and_file_materialize_body(tmp_path):
  # The Materializable surface (glyph tax paid at seed): `.file` is a real tempfile of the body,
  # `.fd` is a process-substitution FD streaming it -- both read the SOURCE, not the run-shadow.
  src = r"""
code.unbound blob(| FDFILE-BODY hi |)
probe:
	@printf 'F=[%s]\n' "`cat $(blob.file)`"
	@printf 'D=[%s]\n' "`cat $(blob.fd)`"
"""
  out = _run(src, tmp_path, cwd=tmp_path)
  assert "F=[FDFILE-BODY hi]" in out
  assert "D=[FDFILE-BODY hi]" in out


def test_tower_membership_reflection(tmp_path):
  # Reflection: a code-object is-a cmk.Fragment (payoff #6) -- it provides the Callable invoke (its
  # own .__call__/.stream), Materializable, and Templatable, so the isinstance/issubclass predicates
  # recognize it as a Fragment (and as Callable/Materializable/Templatable) and it is subclassable.
  src = r"""
code.unbound obj(| body @@h@@ |)
$(info I_MZBL=[$(call isinstance,obj,Materializable)])
$(info I_TMPL=[$(call isinstance,obj,Templatable)])
$(info I_FRAG=[$(call isinstance,obj,cmk.Fragment)])
$(info I_CALL=[$(call isinstance,obj,Callable)])
probe:; @true
"""
  out = _run(src, tmp_path)
  assert "I_MZBL=[1]" in out
  assert "I_TMPL=[1]" in out
  assert "I_FRAG=[1]" in out
  assert "I_CALL=[1]" in out
