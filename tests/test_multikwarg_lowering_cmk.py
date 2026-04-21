"""Multi-kwarg declaration lowering (regression) + the empty-interpreter-binding guard.

A decl with two or more comma-separated PAREN kwargs -- `code NAME(entrypoint=jq, feed=flag,
flag=-f)` -- must lower to a SPACE-separated kwargs string.  A between-kwarg comma is a call-arg
boundary that make splits on: every kwarg after the first lands in a stray positional arg.  A comma
INSIDE a value (`bases=A,B`) is a list and must be preserved.

The EFFECT of the split was front-end-specific: `dsl`/`class` recombine their args via `m5.__splat__`
and so recovered the dropped kwargs (their tests never broke), but `code` reads its first arg only,
so the split collapsed the interpreter binding and the body silently ran as bash.  The lowering fix
below removes the splitting comma at the source (fixing all three uniformly); a future recurrence
(empty entrypoint/img at the interpreter-binding path) now routes to an UNBOUND code-object that
faults with Unbound/Code when run, rather than the silent bash fallthrough.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.compiler]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _transpile(src):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src.encode(),
    capture_output=True,
    timeout=120,
  )
  return r.stdout.decode(errors="replace")


def _run(src, goal, tmp_path):
  f = tmp_path / "t.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(tmp_path),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=180,
  )
  return r.stdout + r.stderr


def test_multikwarg_lowers_space_separated():
  out = _transpile("code p(entrypoint=jq, feed=flag, flag=-f)(| .n |)\n")
  assert "def=p entrypoint=jq feed=flag flag=-f" in out, out
  assert "entrypoint=jq, feed" not in out, out  # no between-kwarg comma survives into the call


def test_list_value_comma_preserved():
  out = _transpile("class C(bases=Dog,Cat, docstrings=1)[| x |]\n")
  assert "bases=Dog,Cat docstrings=1" in out, out  # list comma kept, kwarg boundary -> space


def test_multikwarg_binds_interpreter_not_bash(tmp_path):
  # code reads ${1} only, so this is the path that fell to bash before the fix.  A bound
  # code-object's Runnable slot is `.__in__` (the interpreter binding); an empty binding leaves it unset.
  src = (
    "from cmk import host\n"
    "code jqb(entrypoint=jq, feed=flag, flag=-f)(| .n + 1 |)\n"
    'probe:; @printf "entry=[%s] run=[%s]\\n" "$(jqb.machine._entrypoint)" "$(if $(value jqb.__in__),SET,EMPTY)"\n'
  )
  out = _run(src, "probe", tmp_path)
  assert "entry=[jq] run=[SET]" in out, out  # entrypoint survived the extra kwargs; real binding


def test_dsl_multikwarg_second_kwarg_survives(tmp_path):
  # The dsl/class front-ends recombine via m5.__splat__, so the SECOND kwarg survives independently of
  # the lowering fix -- pinning why polyglot was the only front-end whose binding actually collapsed.
  src = (
    "from cmk import dsl\n"
    "dsl d(entrypoint=bc, feed=stdin)(| |)\n"
    "probe:; @printf 'feed=[%s]\\n' '$(d.machine.feed)'\n"
  )
  out = _run(src, "probe", tmp_path)
  assert "feed=[stdin]" in out, out  # the 2nd kwarg was not dropped


def test_empty_binding_routes_to_unbound(tmp_path):
  # A collapsed/empty interpreter binding (the old multikwarg-drop bug class) no longer runs the
  # body as bash: with entrypoint=/img= effectively empty, `code` routes to an UNBOUND code-object,
  # which faults with Unbound/Code when run (the loud guard is now this structural routing).
  src = (
    "from cmk import host\n"
    "code broken(entrypoint=)(| echo SHOULD-NOT-RUN-AS-BASH |)\n"
    "probe: broken\n"
  )
  out = _run(src, "probe", tmp_path)
  assert "SHOULD-NOT-RUN-AS-BASH" not in out, out   # not silently run as bash
  assert "Unbound/Code" in out, out                  # faults instead
