"""End-to-end for the ordinary-OOP idiom (demos/cmk/banana-oop.cmk).

A class declares methods as recipe targets keyed on `${self}`, the instance.
A subclass names its parent in `bases=` to inherit the whole chain and overrides
a method just by redefining it; with more than one base, resolution follows
Python's order (leftmost wins).  Covered: a base class (Polygon, instance poly),
override + added capability (Rectangle/Rhombus), the leftmost-wins MRO (a Square
is-a Rectangle AND a Rhombus), and per-instance reflection dunders.

Marked `unit` (fast, no docker).  Companion to the compile-level coverage in
test_banana_assign_cmk.py (the `:=` cooked-assignment form the class body uses).
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-oop.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "banana-oop.cmk"


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


def test_demo_runs_clean():
  r, out = _run()
  assert r.returncode == 0, out


def test_class_base_method():
  # Polygon's describe is a recipe target keyed on the instance; poly inherits it.
  r, out = _run("demo.base")
  assert r.returncode == 0, out
  assert "poly is some polygon" in out


def test_subclass_overrides_and_adds_capability():
  # Rectangle overrides describe and adds right_angles; Rhombus overrides describe --
  # each redefinition just shadows the base's target.
  r, out = _run("demo.override")
  assert r.returncode == 0, out
  assert "rect is a rectangle" in out  # Rectangle overrides Polygon.describe
  assert "rect has four right angles" in out  # Rectangle adds right_angles
  assert "rhomb is a rhombus" in out  # Rhombus overrides Polygon.describe


def test_mro_leftmost_base_wins():
  # A Square is-a Rectangle and a Rhombus; both define describe, so the leftmost
  # (Rectangle) wins.
  r, out = _run("demo.mro")
  assert r.returncode == 0, out
  assert re.search(r"bases=\s*Rectangle\s+Rhombus\b", out), out  # ws-tolerant; order meaningful
  assert "sq is a rectangle" in out  # Rectangle.describe, not Rhombus.describe


def test_reflection_dunders():
  # Each instance carries Python-style reflection dunders.
  r, out = _run("demo.reflection")
  assert r.returncode == 0, out
  assert "class=Rectangle" in out
  assert "self=rect" in out


def test_self_binds_to_instance_on_each_method():
  # `${self}` in a class body resolves to the instance name -- the per-instance
  # targets exist and carry the right identity.
  r, out = _run("poly.describe", "rect.right_angles")
  assert r.returncode == 0, out
  assert "poly is some polygon" in out  # Polygon.describe, self=poly
  assert "rect has four right angles" in out  # Rectangle.right_angles


def test_method_scoping_is_per_class():
  # Rhombus has no right_angles, so `rhomb.right_angles` must not exist -- an instance
  # gets only the methods of the classes in its own chain.
  r, out = _run("rhomb.right_angles")
  assert r.returncode != 0
  assert "No rule to make target" in out and "rhomb.right_angles" in out
