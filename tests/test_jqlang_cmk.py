"""Unit tests for the jq-integration primitives that demos/cmk/banana-recipes.cmk
illustrates.  The demo wires them into an illustrative `jqlang` constructor; here we
exercise the PRIMITIVES directly, so the tests track the language, not that demo's
particular shape (a copy of the demo's construct drifts -- see git history):

  * `__locals__`        -- a recipe's shell vars as a JSON object (target_locals pragma)
  * `_mk.def.to.fd`     -- a define fed to `jq -f <(..)` via process substitution
  * `(| filter |)[cmd]` -- the stream callform: run `cmd | filter`, capture stdout

The demo is only smoke-run (exit 0), since it is illustrative, not a contract.

Docker-free (jq / jb / make only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("banana-recipes.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "banana-recipes.cmk"

PRAGMA = '# cmk_pragma ::: { "target_locals": true } :::\n'


def _run(tmp_path, src):
  f = tmp_path / "jql.cmk"
  f.write_text(src)
  return subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )


def test_demo_runs_clean():
  # Illustrative demo -- smoke it (exit 0, no stray shell errors) so it can't rot,
  # without pinning its specific output.  A stale $-level would surface as a
  # `command not found` while still exiting 0 (a broken pipe swallows the code).
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=120,
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "command not found" not in out, out


def test_locals_emits_recipe_vars_as_json(tmp_path):
  # `__locals__` (gated by the target_locals pragma) captures a baseline at recipe
  # entry, then emits the vars the recipe defined as a JSON object.
  p = _run(
    tmp_path,
    PRAGMA
    + "demo:\n\ta <- echo x\n\tb <- echo y\n\t$(__locals__) | ${jq} -c .\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"a":"x"' in p.stdout and '"b":"y"' in p.stdout


def test_locals_without_pragma_degrades(tmp_path):
  # No target_locals pragma -> no baseline -> `__locals__` degrades to `{}` and warns,
  # rather than emitting a bogus object.
  p = _run(
    tmp_path,
    "demo:\n\ta <- echo x\n\t$(__locals__) | ${jq} -c .\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert "target_locals pragma" in out
  assert "{}" in p.stdout


def test_def_to_fd_runs_a_named_jq_program(tmp_path):
  # `_mk.def.to.fd` exposes a define as a process-substitution fd, so a jq PROGRAM can
  # live in a named block and run via `jq -f <(..)`.
  p = _run(
    tmp_path,
    "define prog\n{ echoed: .msg }\nendef\n"
    "demo:\n\t${jb} msg=hi | ${jq} -c -f <($(call _mk.def.to.fd,prog))\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '{"echoed":"hi"}' in p.stdout


def test_stream_callform_pipes_cmd_through_filter(tmp_path):
  # `(| filter |)[cmd]`: run `cmd | filter`, capturing stdout into a make var.
  p = _run(
    tmp_path,
    "r = (| jq -c '{ echoed: .foo }' |)[${jb} foo=bar]\n"
    "demo:; printf '%s\\n' '${r}'\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '{"echoed":"bar"}' in p.stdout


def test_file_materializes_shape_as_tmpfile(tmp_path):
  # `.file` (the fragment MATERIALIZE half) writes the jqlang shape to a real tmpfile whose
  # path can be read by `jq -f`.  Complements `.fd` (process-sub) coverage above.
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang prog(| { echoed: .msg } |)\n"
    "demo:\n\t${jb} msg=hi | ${jq} -c -f ${prog.file}\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '{"echoed":"hi"}' in p.stdout


_CONCAT_KINDS = (
  "from cmk import dsl\n"
  "dsl.jqlang addone(| .n + 1 |)\n"
  "dsl.jqlang double(| . * 2 |)\n"
  "dsl.jqlang wrap(| { result: . } |)\n"
)


def test_pipe_is_CLOSED_composite_runs_and_recomposes(tmp_path):
  # The fragment ALGEBRA (`.__pipe__`, the `cmk.dsl.fragment` seam) is CLOSED: `a.__pipe__(b)`
  # MINTS A FRESH jqlang FRAGMENT (not a shape string), so the result materializes via its OWN .fd,
  # invokes like a leaf, and re-composes.  {n:4}: (.n+1)=5 -> (.*2)=10 -> {result:10}.  The .fd runs
  # (not `jq "<shape>"`) is what distinguishes closed from open.  Both nestings prove associativity /
  # leaf-composite substitutability.  See TODO-dsl-fragment.md.
  p = _run(
    tmp_path,
    _CONCAT_KINDS
    + "mid  := $(call addone.__pipe__,double)\n"
    "full := $(call $(mid).__pipe__,wrap)\n"                             # composite as LHS operand
    "alt  := $(call addone.__pipe__,$(call double.__pipe__,wrap))\n"  # composite as RHS operand
    "__main__:\n"
    "\techo '{\"n\":4}' | ${jq} -c -f $($(mid).fd)\n"
    "\techo '{\"n\":4}' | ${jq} -c -f $($(full).fd)\n"
    "\techo '{\"n\":4}' | ${jq} -c -f $($(alt).fd)\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  lines = [l for l in p.stdout.splitlines() if l.strip()]
  assert lines[0] == "10", out                       # composite invoked via its own .fd
  assert lines[1] == '{"result":10}', out            # 3-deep re-compose (LHS-nested)
  assert lines[2] == '{"result":10}', out            # same, RHS-nested -> associative/substitutable


def test_pipe_hygiene_independent_compositions_dont_collide(tmp_path):
  # Positional gensym: two unrelated compositions in one file mint distinct fragments and both run
  # correctly (no name/shape clobber).  a=(.n+1)|(.*2)=10 ; b=(.*2)|{result:.} on {n:4}.. actually
  # b starts from the raw input, so double|wrap on {"n":4}: (.*2) errors on an object -> use .n first.
  p = _run(
    tmp_path,
    _CONCAT_KINDS
    + "one := $(call addone.__pipe__,double)\n"
    "two := $(call addone.__pipe__,wrap)\n"
    "__main__:\n"
    "\techo '{\"n\":4}' | ${jq} -c -f $($(one).fd)\n"
    "\techo '{\"n\":4}' | ${jq} -c -f $($(two).fd)\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  lines = [l for l in p.stdout.splitlines() if l.strip()]
  assert lines[0] == "10", out                       # (.n+1)|(.*2)
  assert lines[1] == '{"result":5}', out             # (.n+1)|{result:.} -> distinct fragment, no clobber


def test_amp_plus_is_TRUE_string_concat_over_shapes(tmp_path):
  # `+`->.__add__ is TRUE string concatenation (EMPTY joiner) over the shapes -- partial jq expressions
  # join into one program (`.n` + `+1` -> `.n+1`), distinct from `|`->.__pipe__ (jq pipe).  {n:4}: .n+1 = 5.
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang base(| .n |)\n"
    "dsl.jqlang inc(| +1 |)\n"
    "&expr <- base+inc\n"
    "__main__:\n"
    "\techo '{\"n\":4}' | expr(-c)\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert p.stdout.strip() == "5", out


def test_amp_pipe_operator_folds_via___pipe__(tmp_path):
  # `|`->.__pipe__ (jq pipe) -- freed by the `&` gate (bare `|` is a shell pipe).  Same 3-stage
  # pipeline as `+`, via the semantically-honest pipe operator.  {n:4} -> {result:10}.
  p = _run(
    tmp_path,
    _CONCAT_KINDS
    + "&pipeline <- addone|double|wrap\n"
    "__main__:\n"
    "\techo '{\"n\":4}' | pipeline(-c)\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert p.stdout.strip() == '{"result":10}', out



def test_bare_slash_capture_is_shell_NOT_fold(tmp_path):
  # REGRESSION PIN for the `&` gate: WITHOUT `&`, `<-` is an eager SHELL capture, so `out <- dir/file`
  # runs `${make} dir/file` and captures its stdout (here a flux.echo target) -- it must NOT fold into
  # `$(call dir.__div__,file)`.  The fold only fires under `&` (see the amp tests above).
  p = _run(
    tmp_path,
    "import flux\n"
    "demo:\n"
    "\tout <- flux.echo/hello\n"
    "\tprintf '%s\\n' \"$${out}\"\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "hello" in p.stdout, out
  assert "__div__" not in out, out


def test_amp_handle_mints_a_target(tmp_path):
  # `&NAME <- ..` mints a `NAME:` make TARGET twinning the callable macro (`lang.grammar.handle.target`), so
  # `this.NAME` / `${make} NAME` dispatches the handle exactly like `NAME()` does.  {n:4} -> {result:10}.
  p = _run(
    tmp_path,
    _CONCAT_KINDS
    + "&pipeline <- addone|double|wrap\n"
    "__main__:\n"
    "\techo '{\"n\":4}' | this.pipeline\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert '"result": 10' in p.stdout or '{"result":10}' in p.stdout, out


def test_jqlang_is_a_class_conforming_callable(tmp_path):
  # dsl-metaclass tower: `cmk.dsl` mints CLASSES (`cmk.dsl` = `cmk.class` + `cmk.Fragment`, which is
  # `bases=Callable,Materializable`), so jqlang's MRO carries Callable + Materializable + cmk.Fragment,
  # instances have `.__class__`, and a jqlang instance conforms to the `Callable` protocol.  Pins the
  # tower: a revert to a non-class dsl would still pass the fold demos but silently lose reflection /
  # subclassability.
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "dsl.jqlang addone(| .n + 1 |)\n"
    "demo:\n"
    "\t@printf 'mro=[%s] cls=[%s] isa=[%s]\\n' '$(dsl.jqlang.__mro__)' '$(addone.__class__)' '$(call isinstance,addone,Callable)'\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "mro=[Callable Materializable cmk.Fragment dsl.jqlang]" in out, out  # is-a cmk.Fragment is-a Callable
  assert "cls=[dsl.jqlang]" in out, out                          # instance carries .__class__
  assert "isa=[1]" in out, out                                   # conforms to the Callable protocol


def test_dsl_kind_subclassable_qualified(tmp_path):
  # A dsl KIND stays subclassable via its qualified name (`bases=dsl.jqlang`): the subclass keeps its
  # own `.__class__` and the ctor is NOT re-run (which would clobber it -- `tmpl.__class__` would
  # become `dsl.jqlang`, the re-mint would produce a jqlang fragment, and `factor` would reach jq as a
  # filename).  Distilled `demo.subjq`: @@FIELD@@ compile-inject + $factor runtime-inject over {n:4}
  # -> 4*10 = 40.
  p = _run(
    tmp_path,
    "from cmk import dsl\n"
    "from cmk import class\n"
    "class subjq(bases=dsl.jqlang,Templatable)[| ${self}.__call__ = ${jq} $(foreach _kv,$(m5.__splat__),--argjson $(subst =, ,$(_kv)) ) -f $(${self}.fd) |]\n"
    "subjq tmpl(| @@FIELD@@ * $factor |)\n"
    "scaled := $(call tmpl.render,FIELD=.n)\n"
    "demo:\n"
    "\t@printf 'tmpl=[%s] scaled=[%s]\\n' '$(tmpl.__class__)' '$($(scaled).__class__)'\n"
    "\techo '{\"n\":4}' | $(call $(scaled).__call__,factor=10)\n"
    "__main__: demo\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "tmpl=[subjq]" in out, out       # __class__ NOT clobbered to dsl.jqlang (the regression signal)
  assert "scaled=[subjq]" in out, out     # the re-minted fragment is still a subjq
  assert any(l.strip() == "40" for l in p.stdout.splitlines()), out   # subjq's --argjson override won
