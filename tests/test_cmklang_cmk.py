"""Unit tests for `dsl.cmklang` -- the CMK-lang fragment KIND (demos/cmk/module-algebra.cmk).

A cmklang HOLDS its raw CMK-lang shape (cmk.Fragment gives .shape/.fd/.file/.__call__); it does
NOT construct resident `<name>.<target>`s -- that is `cmk.module`'s job (cmk.module = cmklang +
cmk.namespace).  Because it holds instead of constructing, a body `__main__` never leaks to col-0.
Calling a cmklang cooks + re-execs its `__main__` in a child (Program contract), or throws
CMK_NO_MAIN.  `+` (.__add__/.__concat__) concatenates two shapes into a fresh, closed cmklang.

Docker-free (make/bash only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("module-algebra.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

HDR = "from cmk import dsl\n"


def _run(tmp_path, src, goal=None):
  f = tmp_path / "cml.cmk"
  f.write_text(src)
  argv = [str(COMPOSE), "cmk", "run", str(f)] + ([goal] if goal else [])
  return subprocess.run(
    argv,
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )


def test_holds_shape_no_construction(tmp_path):
  # a cmklang HOLDS its shape (Fragment surface: .__class__, .fd) but does NOT construct any
  # `<name>.<target>` -- that is cmk.module's job.  built=n proves the hold (no leak).
  p = _run(
    tmp_path,
    HDR + "dsl.cmklang alpha(|\n  a.hi:; cmk.log(HELD)\n|)\n"
    "__main__:\n"
    "\t@printf 'class=%s fd=%s built=%s\\n' '$(alpha.__class__)' "
    "'$(if $(filter-out undefined,$(origin alpha.fd)),y,n)' "
    "'$(if $(filter-out undefined,$(origin alpha.a.hi)),y,n)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "class=dsl.cmklang" in out, out
  assert "fd=y" in out, out
  assert "built=n" in out, out


def test_call_cooks_and_runs_main(tmp_path):
  # calling a cmklang cooks (JIT-lowers) its raw shape + re-execs the body's __main__ in a child.
  p = _run(
    tmp_path,
    HDR + "dsl.cmklang prog(|\n  __main__: _run\n  _run:; cmk.log(PROG-MAIN)\n|)\n"
    "demo:; prog()\n"
    "__main__: demo\n",
    goal="demo",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "PROG-MAIN" in out, out


def test_call_without_main_throws(tmp_path):
  # a cmklang with no __main__: calling it throws CMK_NO_MAIN (the runtime dual of the
  # static lang.lint.entrypoint advisory), with the aligned "no __main__ entrypoint" message.
  p = _run(
    tmp_path,
    HDR + "dsl.cmklang alpha(|\n  a.hi:; cmk.log(A)\n|)\n"
    "demo:; alpha()\n"
    "__main__: demo\n",
    goal="demo",
  )
  out = p.stdout + p.stderr
  assert p.returncode != 0, out
  assert "CMK_NO_MAIN" in out, out
  assert "no __main__ entrypoint" in out, out


def test_plus_operator_is_closed_and_cooks(tmp_path):
  # `&ab <- lib+entry` folds `+` -> .__add__, concatenating both shapes into a fresh cmklang that
  # is CLOSED over the kind (ab.__class__ is dsl.cmklang).  Cooking ab runs the composed __main__.
  p = _run(
    tmp_path,
    HDR + "dsl.cmklang lib(|\n  say:; cmk.log(COMPOSED)\n|)\n"
    "dsl.cmklang entry(|\n  __main__: say\n|)\n"
    "&ab <- lib+entry\n"
    "check:; @printf 'abclass=%s\\n' '$(ab.__class__)'\n"
    "run:; ab()\n"
    "demo: check run\n"
    "__main__: demo\n",
    goal="demo",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "abclass=dsl.cmklang" in out, out
  assert "COMPOSED" in out, out


def test_concat_dunder_direct(tmp_path):
  # .__concat__ (= .__add__) called directly returns a fresh closed cmklang name; cooking it runs
  # the composed __main__ (both shapes survived the concat).
  p = _run(
    tmp_path,
    HDR + "dsl.cmklang lib(|\n  say:; cmk.log(CATENATED)\n|)\n"
    "dsl.cmklang entry(|\n  __main__: say\n|)\n"
    "$(eval AB := $(call lib.__concat__, entry))\n"
    "check:; @printf 'cls=%s\\n' '$($(AB).__class__)'\n"
    "run:; $(call $(AB).__main__)\n"
    "demo: check run\n"
    "__main__: demo\n",
    goal="demo",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "cls=dsl.cmklang" in out, out
  assert "CATENATED" in out, out


def test_program_default_throws_unconditionally(tmp_path):
  # `bases=Program` (the concretized entrypoint protocol) gives a kind a default `.__main__`
  # that throws CMK_NO_MAIN UNCONDITIONALLY -- a conformer that declares no real entry faults
  # when run.  dsl.cmklang overrides this and reuses the same Program default fault.
  p = _run(
    tmp_path,
    "from cmk import class\n"
    "class prog(bases=cmk.namespace,Program)[| x:; cmk.log(X) |]\n"
    "prog p[| y:; cmk.log(Y) |]\n"
    "demo:; p.__main__()\n"
    "__main__: demo\n",
    goal="demo",
  )
  out = p.stdout + p.stderr
  assert p.returncode != 0, out
  assert "CMK_NO_MAIN" in out, out
  assert "no __main__ entrypoint" in out, out


def test_cmk_module_is_alias_that_constructs(tmp_path):
  # cmk.module = dsl.cmklang + cmk.namespace: it inherits the fragment surface (.fd) but ALSO
  # constructs resident `<name>.<target>`s.  Instances report __class__ == cmk.module.
  p = _run(
    tmp_path,
    "cmk.module m1[| m.hi:; cmk.log(M-HI) |]\n"
    "__main__:\n"
    "\t@printf 'class=%s fd=%s\\n' '$(m1.__class__)' "
    "'$(if $(filter-out undefined,$(origin m1.fd)),y,n)'\n"
    "\t${make} m1.m.hi\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "class=cmk.module" in out, out
  assert "fd=y" in out, out
  assert "M-HI" in out, out


def test_cook_here_runs_an_anonymous_quote_inline(tmp_path):
  # `.__cook_here__` -- the recipe-time cook (materialize the shape in the recipe shell,
  # transpile, run __main__ in a child make) that backs cmk.kernel.  An anonymous
  # `dsl.cmklang(| __main__:; .. |).__cook_here__()` quote cooks + runs INLINE in a recipe,
  # with no tmpfile / mk.compile / mk.interpret.  A recipe shell-var hole fills at cook time.
  p = _run(
    tmp_path,
    HDR + "run:\n"
    "\tx='cmk.log(HOLE-FILLED)'\n"
    "\tdsl.cmklang(| __main__:; ${x} |).__cook_here__()\n"
    "__main__: run\n",
    goal="run",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "HOLE-FILLED" in out, out


def test_code_in_module_is_exec_in_namespace(tmp_path):
  # `(| code |) in M` (the ambient operator) splices code into a MODULE's namespace and cooks it, so the
  # code sees M's targets by SHORT name -- Python's `exec(code, ns)`.  The module dispatches via its
  # `.__in__` dunder (structural Runnable conformance); no `__ambients__` registration needed.  `in`
  # routes host/container/module through one dunder -- no registry, no god-router.
  p = _run(
    tmp_path,
    "from cmk import module\nimport log\n"
    "module M[| greet:; cmk.log(HELLO-FROM-M) |]\n"
    "run:\n"
    "\t@printf 'runnable=%s\\n' '$(call lang.proto.provided_by,M,Runnable)'\n"
    "\t(| this.greet |) in M\n"
    "__main__: run\n",
    goal="run",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "runnable=1" in out, out          # module conforms Runnable via `.__in__` (structural)
  assert "HELLO-FROM-M" in out, out        # short-name `this.greet` resolved in M's namespace


def test_exec_splices_a_full_program(tmp_path):
  # `.__exec__` is the raw splice for a COMPLETE fragment (already carrying its own `__main__`), the
  # primitive under `.__in__` (which wraps a bare lambda body as `__main__` first).
  p = _run(
    tmp_path,
    "from cmk import module\nimport log\n"
    "module M[| greet:; cmk.log(EXEC-FULL-PROG) |]\n"
    "define prog\n__main__:; this.greet\nendef\n"
    "run:; $(call M.__exec__,prog)\n"
    "__main__: run\n",
    goal="run",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "EXEC-FULL-PROG" in out, out
