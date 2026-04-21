"""A `${self}.member(args)` callform lowers for a TARGET member but not a MACRO one.

Inside a class body the `${self}.<member>()` callform is how an instance method is
invoked without the `this.` receiver prefix.  It lowers correctly when `<member>`
is a recipe TARGET: `${self}.tgt()` becomes the sub-make invocation and runs (this
is what let demos/cmk/jqd.cmk convert every `this.alice.start` to `alice.start()`).

It does NOT lower when `<member>` is a parametric MACRO.  `${self}.lg(hi)` reaches
the shell as the literal token `cmk.<self>.lg(hi)` -- the callform/smart-send stage
resolves `${self}.<member>` at lower time, and where a target resolves to a `${make}`
invocation, a `${self}`-qualified macro (whose name is a template placeholder, not a
registered receiver at that point) falls through to a bare `cmk.`-prefixed dispatch
that is emitted verbatim.  The parametric macro must still be invoked the make way,
`$(call ${self}.lg, hi)`.

Two workarounds exist, and the second needs no `$(call)` at the call site: invoke it
the make way (`$(call ${self}.lg, args)`), OR define the member as its `.__call__`
dunder -- the gate's FIRST branch honours `${self}.lg.__call__`, so the callform then
routes correctly.  The dunder path is why demos/cmk/jqd.cmk's `log` verb is a
`${self}.log.__call__` member invoked as `${self}.log(started)`.
"""

import pytest

pytestmark = pytest.mark.compiler


def _run(cmk, tmp_path, invoke, *, lg_dunder=False):
  """A `thing` with a parametric macro (`lg`) and a recipe target (`tgt`); its
  `run` method invokes one of them via `invoke`, dispatched as `t.run()`.  With
  `lg_dunder`, `lg` is defined as its `.__call__` dunder instead of a bare macro."""
  lg = "${self}.lg.__call__" if lg_dunder else "${self}.lg"
  src = tmp_path / "selfcf.cmk"
  src.write_text(
    "from cmk import class\n"
    "class thing[|\n"
    "  " + lg + " = printf 'MACRO:%s\\n' '${__args__}'\n"
    "  ${self}.tgt:; printf 'TARGET-RAN\\n'\n"
    "  ${self}.run:\n"
    f"    {invoke}\n"
    "|]\n"
    "thing t(| |)\n"
    "caller:\n"
    "  t.run()\n"
    "__main__: caller\n"
  )
  return cmk("cmk", "run", str(src), cwd=tmp_path, env={"CMK_SUPERVISOR": "1"}, timeout=120)


def test_target_callform_lowers_in_class_body(cmk, tmp_path):
  # CONTROL: a TARGET member invoked as `${self}.tgt()` lowers to the sub-make call.
  r = _run(cmk, tmp_path, "${self}.tgt()")
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "TARGET-RAN" in r.stdout, out


def test_self_macro_via_make_call_works(cmk, tmp_path):
  # CONTROL / workaround: the parametric macro invoked the make way runs fine.
  r = _run(cmk, tmp_path, "$(call ${self}.lg, hi)")
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "MACRO" in r.stdout and "hi" in r.stdout, out


def test_self_call_dunder_makes_callform_lower(cmk, tmp_path):
  # CONTROL / DESIGNED FIX: define the member's `.__call__` dunder and the
  # `${self}.lg(hi)` callform routes through the gate's first branch
  # (`$(call ${self}.lg.__call__,hi)`) -- no `$(call)` at the call site, no compiler
  # change.  This is why demos/cmk/jqd.cmk's `log` verb is a `.log.__call__` member.
  r = _run(cmk, tmp_path, "${self}.lg(hi)", lg_dunder=True)
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "MACRO" in r.stdout and "hi" in r.stdout, out


@pytest.mark.xfail(
  reason="a BARE `${self}.<macro>(args)` callform does not lower inside a class body: "
  "it leaks the literal token `cmk.<self>.<macro>(args)` to the shell (syntax error), "
  "so the macro never runs.  Only recipe TARGETS lower via the `()` callform; a "
  "parametric macro must be invoked `$(call ${self}.<macro>, args)` OR carry a "
  "`.__call__` dunder (see the two passing controls above).",
  strict=True,
)
def test_self_macro_callform_lowers_in_class_body(cmk, tmp_path):
  # REPRO: identical shape to the target control, but `lg` is a macro.  Desired: the
  # callform lowers like the target one and the macro runs.
  r = _run(cmk, tmp_path, "${self}.lg(hi)")
  out = r.stdout + r.stderr
  assert r.ok, out
  assert "MACRO" in r.stdout and "hi" in r.stdout, out
