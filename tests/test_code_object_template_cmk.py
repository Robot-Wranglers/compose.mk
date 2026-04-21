"""Code-object Templatable surface -- the seed protocol prelude (`lang.proto.tmpl.*`).

A code-object (`code.unbound`/`code.unbound`) is minted off-tower by `_code.unbound`,
not the class engine, so it historically had none of the fragment surface.  It now consumes the
shared seed prelude:

  * `lang.proto.tmpl.materializable` -- gives `.shape` (the body), `.__raw_body__`, `.__blockref__`
  * `lang.proto.tmpl.templatable`       -- gives `.render`/`.__mod__` (compile-time `@@hole@@` fill +
                                        re-mint under the object's own minter)

These are the SAME bodies the hosted `Materializable`/`Templatable` protocols carry, so a dsl fragment
(jqlang) and a code-object share one definition.  Here we exercise the code-object side end to end;
the dsl side is covered by test_jqlang_cmk / test_hosted_cmk (both must stay green -- the shared
bodies are behavior-preserving).

Docker-free (make only).
"""

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path, src, goal="probe"):
  f = tmp_path / "co.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  return r.stdout + r.stderr


# A code-object plus module-level `$(info)` probes (parse-time, so no recipe shell-quoting eats the
# templated body).  `_r` captures the render once at module scope (a recipe-line `$(eval)` collides
# with the recipe joiner).
PROBE = r"""
code.unbound greeting(| hello @@who@@ from @@place@@ |)

_r := $(call greeting.render,who=bob place=NYC)

$(info CO_SHAPE=[$(value greeting.shape)])
$(info CO_MINT=[$(greeting.__ctor__)])
$(info CO_RAWBODY=[$(origin greeting.__raw_body__)])
$(info CO_RENDER_NAME=[$(_r)])
$(info CO_RENDER_SHAPE=[$(value $(_r).shape)])
$(info CO_RENDER_MINT=[$($(_r).__ctor__)])

probe:; @true
"""


def test_code_object_exposes_shape(tmp_path):
  # Materializable prelude: a code-object's `.shape` is its raw body (with holes intact).
  out = _run(tmp_path, PROBE)
  assert "CO_SHAPE=[hello @@who@@ from @@place@@]" in out
  assert "CO_RAWBODY=[file]" in out  # .__raw_body__ stamped from the prelude


def test_code_object_mint_is_dollar1_minter(tmp_path):
  # `.__ctor__` is the `$1`-form minter so the Templatable re-mint's `def=` reaches the constructor.
  out = _run(tmp_path, PROBE)
  assert "CO_MINT=[code.unbound]" in out


def test_render_fills_and_remints_same_kind(tmp_path):
  # Templatable prelude: `.render(k=v ..)` fills every hole and re-mints a fresh SAME-KIND object.
  out = _run(tmp_path, PROBE)
  assert "CO_RENDER_NAME=[__frag_" in out           # a fresh minted fragment
  assert "CO_RENDER_SHAPE=[hello bob from NYC]" in out  # multi-pair fill
  assert "CO_RENDER_MINT=[code.unbound]" in out  # same kind (code-object)


def test_render_multipair_and_repeat_hole(tmp_path):
  # A hole repeated in the body fills every occurrence; N pairs fold in one call.
  src = r"""
code.unbound t(| @@a@@-@@b@@-@@a@@ |)
_r := $(call t.render,a=X b=Y)
$(info MP=[$(value $(_r).shape)])
probe:; @true
"""
  out = _run(tmp_path, src)
  assert "MP=[X-Y-X]" in out


def test_source_object_unmutated_by_render(tmp_path):
  # `.render` is non-destructive: the source object's shape still holds the holes afterwards.
  src = r"""
code.unbound s(| keep @@h@@ |)
_r := $(call s.render,h=filled)
$(info SRC=[$(value s.shape)])
$(info OUT=[$(value $(_r).shape)])
probe:; @true
"""
  out = _run(tmp_path, src)
  assert "SRC=[keep @@h@@]" in out
  assert "OUT=[keep filled]" in out


def test_render_preserves_bind(tmp_path):
  # Bind-preserving render (payoff #4 enabler): rendering a BOUND code-object yields a still-bound
  # object -- re-minted carrying the original kwargs, not the unbound bare-minter default -- so the
  # specialization stays runnable.  Unbound originals stay unbound (the tests above).
  src = r"""
code q(bind=host.local)(| body @@h@@ |)
_r := $(call q.render,h=filled)
$(info REND_SHAPE=[$(value $(_r).shape)])
$(info REND_MACHINE=[$(value $(_r).__machine__)])
$(info REND_MINT=[$($(_r).__ctor__)])
probe:; @true
"""
  out = _run(tmp_path, src)
  assert "REND_SHAPE=[body filled]" in out       # template filled
  assert "REND_MACHINE=[host.local]" in out       # bind preserved (was dropped before the fix)
  assert "REND_MINT=[code.unbound]" in out  # still the same kind


@pytest.mark.skipif(not shutil.which("python3"), reason="needs host python3")
def test_render_then_call_with_argv(tmp_path):
  # #4 end to end: template-fill (compile time) x argv (runtime) compose in ONE body for an
  # interpreter that reads argv without `$` (python's sys.argv, which does not collide with the
  # render `$`-expansion the way a shell `$@`/`$1` would).  render keeps the object runnable.
  src = r"""
from cmk import host
code q(entrypoint=python3)(|
  import sys
  print("t=@@t@@ argv=%s" % sys.argv[1:])
|)
u := $(call q.render,t=users)
run:; $(call $(u).__call__,42 99)
"""
  out = _run(tmp_path, src, goal="run")
  assert "t=users argv=['42', '99']" in out, out
