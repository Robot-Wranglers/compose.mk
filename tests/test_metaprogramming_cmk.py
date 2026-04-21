"""End-to-end for the golden metaprogramming demo (demos/cmk/metaprogramming.cmk).

Covers the constructor family proven in isolation: class + inline body (Crew, whose
report method is a recipe target keyed on the instance), dsl instances callable via
a callform (bclang), inheritance with override (Squad is-a Crew), the class
umbrella (a module of child kinds via umbrella=1), and protocol mixins (Greetable).

These assert OUTPUT, not just exit code.  The constructs lower to make macro
plumbing where a wrong $-level fails SILENTLY: a doubled $ in a body collapses to a
shell PID or a `command not found`, but the surrounding `printf | tr` pipe (or a
stray `${make}` dispatch) still exits 0.  A smoke test that checks only returncode
misses it -- which is exactly how the demo regressed unnoticed when capture-based
instantiation made bodies single-$.

Marked `unit` (fast, no docker).
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("metaprogramming.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "metaprogramming.cmk"


def _run(*targets, timeout=90):
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO), *targets],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def _run_src(tmp_path, src, timeout=90):
  # Run a self-contained snippet -- for mechanism tests that shouldn't ride on the
  # illustrative demo's specific output.
  f = tmp_path / "mp.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r


def test_demo_runs_clean():
  r, out = _run()
  assert r.returncode == 0, out
  # The tells of a wrong $-level, which exit 0 on their own -- guard them directly
  # so a stale doubled-$ can never hide behind a green smoke test again.
  assert "command not found" not in out, out
  assert "warning:" not in out, out


def test_class_inline_body_methods_keyed_on_instance():
  # Crew declares report as an inline recipe target keyed on ${self}; each instance
  # gets its own report that names itself (a single-$ ${self} deref, resolved at
  # build time -- a doubled $ would collapse to a PID here).
  r, out = _run("demo.class")
  assert r.returncode == 0, out
  assert "baker standing by" in out
  assert "cook standing by" in out


def test_dsl_instance_callable_named_and_anonymous(tmp_path):
  # A dsl instance body is data its kind reads back with $(value self); the kind makes the
  # instance callable.  Named -> a bare NAME() callform; anonymous -> KIND(|..|).eval(),
  # lifted inline at recipe level (the anon-immediate needs a method, not a bare `()`).
  # Self-contained (a minimal calc kind), so it tests the mechanism, not the demo's program.
  r = _run_src(
    tmp_path,
    "open cmk\n"
    "dsl calc[|\n"
    "  ${self}.src := $(value ${self})\n"
    "  ${self} = printf '%s\\n' '$(${self}.src)' | bc\n"
    "  ${self}.eval = $(call ${self})\n"
    "|]\n"
    "calc twice(| 2 * 21 |)\n"
    "demo:\n\ttwice()\n\tcalc(| 9 * 9 |).eval()\n"
    "__main__: demo\n",
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "command not found" not in out, out  # a wrong $-level would surface here
  assert "42" in r.stdout                      # named: 2 * 21 via the bare callform
  assert "81" in r.stdout                      # anonymous: 9 * 9 via the anon-immediate .eval()


def test_reflection_dunders():
  # a class mints per-instance dunders; the docstring lives on the KIND and is
  # reflected through the instance's __class__ (Python's inst.__doc__ lookup).
  r, out = _run("demo.reflection")
  assert r.returncode == 0, out
  assert "cls" in out and "Crew" in out          # cook.__class__
  assert "self" in out and "baker" in out        # baker.__im_self__
  assert "Crew: a base class" in out             # $(${cook.__class__}.__doc__)


def test_inheritance_overrides_report():
  # Squad is-a Crew that overrides the RECIPE TARGET report: the engine strips Crew's
  # copy so make sees one recipe (no `overriding recipe` warning).  baker keeps Crew's
  # report, sergeant gets Squad's override.
  r, out = _run("demo.inherit")
  assert r.returncode == 0, out
  assert re.search(r"bases=\s*Crew\b", out), out    # Squad.__bases__ reflects the parent (ws-tolerant)
  assert "baker standing by" in out                # baker keeps Crew's report target
  assert "sergeant sounding off" in out            # sergeant gets Squad's report override
  assert "overriding recipe" not in out            # direct target override is warning-free


def test_umbrella_namespaces_kind_and_aliases_leaf():
  # `class polyhedra(umbrella=1)` makes polyhedra a module: `polyhedra octahedron` mints the child
  # KIND polyhedra.octahedron, auto-registers it in polyhedra.__all__, and the bare leaf name is
  # bound as a forward-alias of the FQN (same mro, canonical identity stays the FQN).
  r, out = _run("demo.umbrella")
  assert r.returncode == 0, out
  assert "tetrahedron octahedron dodecahedron" in out              # auto-manifest, no manual seed
  assert "mro = Loggable Named polyhedra.octahedron" in out        # child kind under the module
  assert "bare alias" in out and "octahedron mro = Loggable Named polyhedra.octahedron" in out


def test_protocol_mixin_default_and_override():
  # cmk.protocol mints a mixin + a default impl: Robot overrides greet, Plant inherits
  # the protocol's default; the abstract contract member reflects on the kind.
  r, out = _run("demo.protocol")
  assert r.returncode == 0, out
  assert "r2d2.greet=greet.loud" in out       # class override (last write wins)
  assert "fern.greet=greet.default" in out    # inherited protocol default
  assert "Greetable.abstract=greet" in out    # the contract member
