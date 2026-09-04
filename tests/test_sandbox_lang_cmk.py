"""CMK-lang feature characterizations, driven through the REAL compiler via the `sandbox`
injection harness (conftest.py's `sandbox` fixture).  Each test either RUNs an injected snippet
and asserts on behavior, or COMPILEs it and asserts on the lowered makefile text (`.compiled`).

These pin how the compiler treats callforms, qualified/unqualified names, handle-assignments
(`<-`), and cooked-vs-raw classes with docstrings -- so a change in any of those lowerings is
caught here as a test flip, rather than surfacing downstream as `__hosted__` flakiness.
"""

import pytest

# This file characterizes COMPILER lowerings (callforms, names, handle-assigns,
# cooked-vs-raw class docstrings) -- half its cases assert on `.compiled` transpile
# text via the no-docker `sandbox.compile`.  It must run in the `compiler` gate, not
# just `unit`; being `unit`-only was a blind spot that let lowering regressions ship.
pytestmark = [pytest.mark.unit, pytest.mark.compiler]


# --- Callforms: `cmk.NAME(args)` -> `$(call NAME,args)` ------------------------------------


def test_callform_cmk_prefixed_lowers(sandbox):
  # The `cmk.` prefix is the trigger: a callform lowers to `$(call ..)`, prefix stripped.
  r = sandbox.compile("probe:\n  cmk.log(hi there)")
  assert r.compiled is not None, r.output
  assert "$(call log,hi there)" in r.compiled, r.compiled


def test_callform_bare_is_not_lowered(sandbox):
  # A BARE callform (no `cmk.` prefix) at recipe level is left verbatim -- the prefix marks it.
  r = sandbox.compile("probe:\n  foo(a, b, c)")
  assert r.compiled is not None, r.output
  assert "foo(a, b, c)" in r.compiled, r.compiled
  assert "$(call foo" not in r.compiled, r.compiled


def test_callform_qualified_and_unqualified_names(sandbox):
  # Qualified (dotted) and unqualified callform names lower the same way: only `cmk.` is stripped;
  # whatever remains (dotted or bare) becomes the `$(call)` target.
  r = sandbox.compile("probe:\n  cmk.log(q)\n  cmk.foo(u)")
  assert r.compiled is not None, r.output
  assert "$(call log,q)" in r.compiled, r.compiled  # qualified -> log
  assert "$(call foo,u)" in r.compiled, r.compiled  # unqualified -> foo


# --- Handle-assignments: `[&]NAME <- <expr>` ----------------------------------------------


def test_handle_assign_arrow_is_shell_capture(sandbox):
  # `NAME <- expr` in a recipe lowers to a shell command-substitution capture.
  r = sandbox.compile("probe:\n  result <- echo hello")
  assert r.compiled is not None, r.output
  assert "result=`echo hello`" in r.compiled, r.compiled


def test_handle_assign_arrow_captures_at_runtime(sandbox):
  # `<-` captures into a SHELL variable (the capture + next line are joined into one shell), so it
  # is read as `$${result}` (make-escaped `$`); a single-`$` `${result}` would be a make var
  # (empty).  The two recipe lines run in the same shell, so the captured value is visible.
  body = "probe:\n  result <- echo captured-ok\n  @echo got=[$${result}]"
  r = sandbox.run(body, goal="probe")
  assert r.ok, r.output
  assert "got=[captured-ok]" in r.stdout, r.output


def test_handle_assign_ampersand_is_make_var(sandbox):
  # The `&` handle marker makes it a MAKE-level assignment (no shell exec): `&h <- expr` -> `h = expr`.
  r = sandbox.compile("probe:\n  &h <- echo handle-value")
  assert r.compiled is not None, r.output
  assert "h = echo handle-value" in r.compiled, r.compiled


# --- Cooked classes with docstrings -------------------------------------------------------


@pytest.mark.docstring
def test_cooked_class_docstring_lowers_to_eval_define(sandbox):
  # A cooked class docstring is ALWAYS-LIFTED (fragdoc_capture) to a top-level
  # `$(eval define <Name>.__doc__ .. endef)` -- name-scoped on the class, with a clean body.
  r = sandbox.compile("cmk.class Widget(|\n  '''a widget'''\n  ${self}.color := blue\n|)")
  assert r.compiled is not None, r.output
  assert "Widget.__doc__" in r.compiled, r.compiled
  assert "a widget" in r.compiled, r.compiled


@pytest.mark.docstring
def test_cooked_class_docstring_binds_to_class_not_instance(sandbox):
  # The docstring binds to the CLASS name (`Widget.__doc__`, always-lifted); the instance sugar
  # (`Widget w1(| |)`) stamps `.color`/`.__class__` but NOT a per-instance `.__doc__` -- the
  # per-instance re-lift (the `Described` mixin) was removed in favor of name-scoped always-lift.
  body = (
    "cmk.class Widget(|\n"
    "  '''a widget'''\n"
    "  ${self}.color := blue\n"
    "|)\n"
    "Widget w1(| |)\n"
    "probe:\n"
    "\t@echo classdoc=[${Widget.__doc__}] instdoc=[${w1.__doc__}] color=[${w1.color}] class=[${w1.__class__}]"
  )
  r = sandbox.run(body, goal="probe")
  assert r.ok, r.output
  assert "classdoc=[a widget]" in r.stdout, r.output   # the doc lives on the class
  assert "instdoc=[]" in r.stdout, r.output             # NOT copied to the instance
  assert "color=[blue]" in r.stdout, r.output
  assert "class=[Widget]" in r.stdout, r.output


# --- Cooked vs raw classes ----------------------------------------------------------------


def test_raw_class_constructs_instance(sandbox):
  # A RAW class (`define ..endef` + `$(eval $(call cmk.class,def=..))`) constructs instances too
  # -- it is the make-level substrate a cooked class lowers onto.  Members present; no docstring.
  body = (
    "define Gadget\n"
    "${self}.color := red\n"
    "endef\n"
    "$(eval $(call cmk.class, def=Gadget))\n"
    "$(eval $(call Gadget, def=g1))\n"
    "probe:\n"
    "\t@echo color=[${g1.color}] class=[${g1.__class__}]"
  )
  r = sandbox.run(body, goal="probe")
  assert r.ok, r.output
  assert "color=[red]" in r.stdout, r.output
  assert "class=[Gadget]" in r.stdout, r.output


def test_cooked_and_raw_class_are_equivalent(sandbox):
  # Same instance behavior from both authoring forms (the point of "cooked lowers to raw").
  cooked = sandbox.run(
    "cmk.class C(|\n  ${self}.v := 42\n|)\nC c1(| |)\nprobe:\n\t@echo [${c1.v}][${c1.__class__}]",
    goal="probe",
  )
  raw = sandbox.run(
    "define C\n${self}.v := 42\nendef\n$(eval $(call cmk.class, def=C))\n"
    "$(eval $(call C, def=c1))\nprobe:\n\t@echo [${c1.v}][${c1.__class__}]",
    goal="probe",
  )
  assert cooked.ok and raw.ok, (cooked.output, raw.output)
  assert "[42][C]" in cooked.stdout, cooked.output
  assert "[42][C]" in raw.stdout, raw.output


@pytest.mark.docstring
def test_raw_class_docstring_is_opaque_and_breaks(sandbox):
  # THE cooked-vs-raw distinction: a raw `define` is OPAQUE to the moduledoc/triplequote stage, so
  # a `'''docstring'''` inside it is NOT lowered -- it stays literal and breaks make when the class
  # body is applied (a bare `'''..'''` line is not a valid statement).  Cooking is what makes
  # docstrings work; this is why hosted classes are authored as cooked bananas, not raw defines.
  body = (
    "define Gadget\n"
    "'''a raw docstring'''\n"
    "${self}.x := 1\n"
    "endef\n"
    "$(eval $(call cmk.class, def=Gadget))\n"
    "$(eval $(call Gadget, def=g1))\n"
    "probe:\n"
    "\t@echo ${g1.x}"
  )
  r = sandbox.run(body, goal="probe")
  assert not r.ok, r.output
  assert "missing separator" in r.output, r.output
  # the docstring survived verbatim in the built cache (opaque), never lowered to `__doc__`.
  if r.compiled:
    assert "'''a raw docstring'''" in r.compiled, r.compiled
