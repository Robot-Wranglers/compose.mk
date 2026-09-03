"""Unit tests for machine-backed `dsl` kinds (demos/cmk/dsl-bclang.cmk).

A `dsl` kind is normally a fragment leaf whose base call is hand-written (jqlang: `jq -f`).
Machine-backing is the composition alternative: `dsl NAME(entrypoint=X)(| |)` mints a machine
for the kind and every instance runs its `.shape` through it (materialize + entrypoint), so the
fragment (a Callable) delegates its invoke to a machine (a Runnable) -- has-a, not is-a.  A plain
`dsl` with no such kwargs stays a leaf and keeps its own base call (no `.__machine__`).

Docker-free (bc/make/bash only).
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.covers_demo("dsl-bclang.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

HDR = "from cmk import dsl\n"


def _run(tmp_path, src, goal=None):
  f = tmp_path / "dm.cmk"
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


def test_named_instance_runs_through_machine(tmp_path):
  # a named machine-backed instance is callable by name; its shape runs through the kind's machine.
  p = _run(
    tmp_path,
    HDR + "dsl bclang(entrypoint=bc)(| |)\n"
    "bclang area(| 3.14159 * 5 ^ 2 |)\n"
    "__main__:\n\tarea()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "78.53975" in out, out


def test_anonymous_instance_runs_inline(tmp_path):
  # an anonymous instance runs inline via .__call__(), also through the machine.
  p = _run(
    tmp_path,
    HDR + "dsl bclang(entrypoint=bc)(| |)\n"
    "__main__:\n\tbclang(| 5 ^ 3 |).__call__()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "125" in out, out


def test_kind_records_its_machine(tmp_path):
  # a machine-backed kind records its shared machine as <kind>.__machine__ (an instance name), and
  # that machine exists (has a .run).  Instances resolve it via their class.  Under the dsl umbrella
  # the kind is dsl.bclang, so its machine is dsl.bclang.machine (bare `bclang` is a forward-alias).
  p = _run(
    tmp_path,
    HDR + "dsl bclang(entrypoint=bc)(| |)\n"
    "bclang area(| 1 + 1 |)\n"
    "__main__:\n"
    "\t@printf 'kmach=%s imach=%s run=%s\\n' '$(bclang.__machine__)' "
    "'$(area.__machine__)' "
    "'$(if $(filter-out undefined,$(origin $(bclang.__machine__).run)),y,n)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "kmach=dsl.bclang.machine" in out, out
  assert "imach=dsl.bclang.machine" in out, out
  assert "run=y" in out, out


def test_bind_existing_machine(tmp_path):
  # the escape hatch: `machine=X` binds an already-minted machine instead of minting one, so a
  # fancy machine (a container, a built image) can back the kind.  The kind records X verbatim.
  p = _run(
    tmp_path,
    "from cmk import dsl, machine\n"
    "machine mybc(| entrypoint=bc |)\n"
    "dsl calc(machine=mybc)(| |)\n"
    "calc sq(| 9 * 9 |)\n"
    "__main__:\n"
    "\t@printf 'mach=%s\\n' '$(sq.__machine__)'\n"
    "\tsq()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "mach=mybc" in out, out
  assert "81" in out, out


def test_plain_dsl_has_no_machine(tmp_path):
  # a plain leaf dsl (no entrypoint/img/machine kwargs) is NOT machine-backed: no .__machine__,
  # so it keeps its own hand-written base call (the jqlang/awklang path is untouched).
  p = _run(
    tmp_path,
    HDR + "dsl plainlang(| |)\n"
    "plainlang leaf(| x |)\n"
    "__main__:\n"
    "\t@printf 'mach=[%s]\\n' '$(leaf.__machine__)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "mach=[]" in out, out


def test_bind_bare_target(tmp_path):
  # `bind=T` binds a bare unary file-target (not a machine): the shape reaches T as a FILE via the
  # file-seam (io.with.file), the same path a polyglot code-object binds through.  Unified on
  # `.__machine__` with machine=/entrypoint=, but the proxy picks the file-seam (T has no `.__in__`).
  p = _run(
    tmp_path,
    HDR + "my_interp/%:; @cat ${*}\n"
    "dsl echoer(bind=my_interp)(| |)\n"
    "echoer greeting(| hello from bind |)\n"
    "__main__:\n"
    "\t@printf 'mach=%s\\n' '$(greeting.__machine__)'\n"
    "\tgreeting()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "mach=my_interp" in out, out
  assert "hello from bind" in out, out


def test_feed_flag_discipline(tmp_path):
  # feed=flag routes the shape after a flag (jq -f), args/data still on stdin: the shape is a jq
  # program fed via -f, the recipe pipes the JSON.
  p = _run(
    tmp_path,
    HDR + "dsl jqf(entrypoint=jq, feed=flag, flag=-f)(| |)\n"
    "jqf pick(| .n |)\n"
    "__main__:\n\tprintf '{\"n\":42}' | pick()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "42" in out, out


def test_feed_stdin_discipline(tmp_path):
  # feed=stdin pipes the shape itself to the interpreter (no file argument): a bc calculator whose
  # program arrives on stdin.
  p = _run(
    tmp_path,
    HDR + "dsl bcs(entrypoint=bc, feed=stdin)(| |)\n"
    "bcs calc(| 6 * 7 |)\n"
    "__main__:\n\tcalc()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "42" in out, out


def test_feed_defaults_to_file(tmp_path):
  # feed absent == feed=file (the shape is a file argument); a machine records feed=file and IS-A
  # Feedable structurally.  This pins the back-compat default.
  p = _run(
    tmp_path,
    HDR + "dsl bcf(entrypoint=bc)(| |)\n"
    "bcf area(| 2 ^ 10 |)\n"
    "__main__:\n"
    "\t@printf 'feed=%s isa=%s\\n' '$(bcf.machine.feed)' '$(call isinstance,bcf.machine,Feedable)'\n"
    "\tarea()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "feed=file isa=1" in out, out
  assert "1024" in out, out


# --- anonymous-instance callform grammar ---------------------------------------------------------
# Intended grammar for an anonymous instance:
#   X(a,b)(| body |)  = CONSTRUCTOR args (a,b) + body  (GAP: still unsupported, xfail below)
#   X(| body |)(a,b)  = construct, then CALL the instance with (a,b)  (== `.__call__(a,b)`)


def test_trailing_paren_invokes_the_instance(tmp_path):
  # `X(| body |)()` on a constructor-kind (dsl) constructs the instance and invokes IT -- routed by the
  # receiver carrying `.__tmpl`.  (Was: mis-lowered to the kind's empty-shape call; needed `.__call__()`.)
  p = _run(
    tmp_path,
    HDR + "dsl bclang(entrypoint=bc feed=stdin)(| |)\n"
    "__main__:\n\tbclang(| 5 ^ 3 |)()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0 and "125" in out, out


def test_trailing_paren_machine_still_runs(tmp_path):
  # A machine receiver is NOT a constructor-kind (no `.__tmpl`), so trailing `M(| body |)()` stays on
  # the kind-call blockref path (run the block through the machine).  Guards the discrimination.
  p = _run(
    tmp_path,
    "from cmk import host\n"
    "__main__:\n\thost.native.sh(| echo MACHINE_OK |)()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0 and "MACHINE_OK" in out, out


@pytest.mark.xfail(
  reason="leading ctor-args `X(a,b)(| body |)` unsupported: emits "
  "`block ...: using/paren kwargs with no PREFIX constructor`.  ctor-args-before-body is the "
  "intended grammar (piece 2)."
)
def test_leading_paren_is_ctor_args(tmp_path):
  # EXPECTED: a paren BEFORE the banana carries constructor args; today it is a compile error.
  p = _run(
    tmp_path,
    HDR + "dsl bclang(entrypoint=bc feed=stdin)(| |)\n"
    "__main__:\n\tbclang(a,b)(| 2 + 2 |)\n",
  )
  assert p.returncode == 0, p.stdout + p.stderr


def _doc_src(kw):
  # a cat/feed=stdin DSL echoes its shape, so a docstring left in the shape surfaces in the output.
  # `kw` is the extra decl kwarg(s) after entrypoint/feed (e.g. "" / ", docstrings=0").
  return (
    HDR + "dsl catlang(entrypoint=cat, feed=stdin%s)(| |)\n" % kw
    + "catlang prog(|\n''' LEAKMARKER doc '''\nPAYLOAD_LINE\n|)\n"
    + "__main__:\n\tprog()\n"
  )


@pytest.mark.docstring
@pytest.mark.parametrize("kw", ["", ", docstrings=1"])
def test_docstrings_default_lifts_instance_doc(tmp_path, kw):
  # A `dsl` body is a raw fragment shape, so a leading `'''..'''` in an instance is lifted to
  # `NAME.__doc__` BY DEFAULT (and `docstrings=1` is the same).  The opt-in appends to _cmk.doc.kinds
  # only at eval -- after this file's transpile -- so it can't reach the FRAGKINDS baked into the
  # compile stage; the moduledoc stage self-registers the kind from the decl (decl precedes instances).
  p = _run(tmp_path, _doc_src(kw))
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "PAYLOAD_LINE" in out, out          # the shape ran through the machine
  assert "LEAKMARKER" not in out, out        # the docstring was lifted, not left in the shape
  assert "$(eval" not in out, out            # no make carrier polluting the program
  # and the lifted docstring binds to the instance's `.__doc__`.
  d = _run(tmp_path, _doc_src(kw), goal="mk.get/prog.__doc__")
  assert "LEAKMARKER doc" in (d.stdout + d.stderr), d.stdout + d.stderr


@pytest.mark.docstring
def test_docstrings_zero_leaves_triplequote_literal(tmp_path):
  # `docstrings=0` opts OUT: a leading `'''..'''` is left VERBATIM in the shape (for a language that
  # needs it as literal data), never lifted and -- unlike an unregistered kind -- never turned into an
  # `$(eval ..)` carrier.  So cat echoes the triple-quote, and `.__doc__` is NOT the instance's text.
  p = _run(tmp_path, _doc_src(", docstrings=0"))
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "'''" in out and "LEAKMARKER doc" in out, out   # triple-quote kept literal in the shape
  assert "$(eval" not in out, out                        # not the broken inline-carrier path
  d = _run(tmp_path, _doc_src(", docstrings=0"), goal="mk.get/prog.__doc__")
  assert "LEAKMARKER doc" not in (d.stdout + d.stderr), d.stdout + d.stderr   # not lifted to __doc__


# --- dsl namespace: `dsl NAME` -> child kind `dsl.NAME` by default (TODO-dsl-umbrella.md) ---------
# `dsl` is a module of class-kinds: a bare `dsl foo` mints the child kind `dsl.foo` (the ONE
# canonical identity), carries its body onto that FQN, registers `foo` in `dsl.__all__`, and binds
# the bare leaf `foo` as a forward-alias of `dsl.foo`.  Symmetric with the built-in `dsl.jqlang`.


def test_dsl_default_namespaces_kind_and_runs(tmp_path):
  # a bare `dsl NAME(...)` mints the functional kind `dsl.NAME`; instances mint under it and run.
  p = _run(
    tmp_path,
    HDR + "dsl mylang(entrypoint=bc feed=stdin)(| |)\n"
    "dsl.mylang area(| 3 * 3 |)\n"
    "__main__:\n"
    "\t@printf 'kind=%s mint=%s\\n' "
    "'$(if $(filter-out undefined,$(origin dsl.mylang.__mro__)),y,n)' '$(area.__ctor__)'\n"
    "\tarea()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "kind=y" in out, out              # `dsl.mylang` is the functional kind
  assert "mint=dsl.mylang" in out, out     # instances carry the qualified kind as their mint
  assert "9" in out, out                   # construct + run through the machine


def test_dsl_bare_leaf_is_forward_alias(tmp_path):
  # the bare leaf `mylang` is bound as a forward-alias of `dsl.mylang` -- same mro (which NAMES the
  # FQN, the one canonical identity), so bare use resolves through to the qualified kind.
  p = _run(
    tmp_path,
    HDR + "dsl mylang(entrypoint=bc feed=stdin)(| |)\n"
    "__main__:\n"
    "\t@printf 'alias=[%s] fqn=[%s]\\n' '$(mylang.__mro__)' '$(dsl.mylang.__mro__)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "alias=[Callable Materializable cmk.Fragment dsl.mylang]" in out, out
  assert "fqn=[Callable Materializable cmk.Fragment dsl.mylang]" in out, out


def test_dsl_leaf_base_call_survives_namespace(tmp_path):
  # a LEAF dsl (hand-written `${self} = <base call>`, like jqlang) keeps its base call under the
  # namespace: the body is carried onto `dsl.NAME`, so instances run the base call, not the raw shape.
  p = _run(
    tmp_path,
    HDR + "dsl jqish[| ${self} = ${jq} ${__args__} -f ${self}.fd() |]\n"
    "dsl.jqish pick(| .n |)\n"
    "__main__:\n\tprintf '{\"n\":99}' | pick()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "99" in out, out


def test_dsl_kind_single_identity(tmp_path):
  # the kind keeps ONE identity: an instance is-a `dsl.NAME` AND is-a `cmk.Fragment` via the mro.
  p = _run(
    tmp_path,
    HDR + "dsl echoer(entrypoint=cat feed=stdin)(| |)\n"
    "dsl.echoer inst(| hi |)\n"
    "__main__:\n"
    "\t@printf 'isa_kind=%s isa_frag=%s\\n' "
    "'$(call isinstance,inst,dsl.echoer)' '$(call isinstance,inst,cmk.Fragment)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "isa_kind=1 isa_frag=1" in out, out


def test_dsl_named_after_a_make_builtin_is_rejected(tmp_path):
  # the declaration is refused instead of silently running the body on the host.
  p = _run(
    tmp_path,
    HDR + "dsl shell(entrypoint=bc)(| |)\n"
    "shell area(| 3.14159 * 5 ^ 2 |)\n"
    "__main__:\n\tarea()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode != 0, out
  assert "errno=CLASS_DECL" in out and "collides with a make builtin" in out, out
  assert "3.14159: command not found" not in out, out


def test_class_named_after_a_make_builtin_is_rejected(tmp_path):
  # the hazard is the kind name heading each instance declaration, so it is not dsl-specific.
  p = _run(
    tmp_path,
    "cmk.class shell(| ${self}.hello:; echo HELLO-DISPATCHED |)\n"
    "shell t(| |)\n"
    "__main__:\n\tthis.t.hello\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode != 0, out
  assert "errno=CLASS_DECL" in out and "collides with a make builtin" in out, out


def test_dotted_dsl_name_over_a_builtin_basename_is_legal(tmp_path):
  # only the bare name collides: a dotted name is not a make function.
  p = _run(
    tmp_path,
    HDR + "dsl bashish.if(entrypoint=bc)(| |)\n"
    "bashish.if area(| 3.14159 * 5 ^ 2 |)\n"
    "__main__:\n\tarea()\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "78.53975" in out, out


def test_instance_named_after_a_make_builtin_is_legal(tmp_path):
  # an instance name is not a declarator head, so it does not collide and stays allowed.
  p = _run(
    tmp_path,
    "cmk.class calcish(| ${self}.hello:; echo HELLO-DISPATCHED |)\n"
    "calcish sort(| |)\n"
    "__main__:\n\tthis.sort.hello\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "HELLO-DISPATCHED" in out, out


def test_dsl_manifest_populates_and_imports(tmp_path):
  # every `dsl NAME` self-registers in the `dsl` module manifest, so `from dsl import NAME` binds the
  # bare name -- the same module machinery as the built-in `dsl.jqlang` (no manual manifest seed).
  p = _run(
    tmp_path,
    HDR + "dsl mylang(entrypoint=bc feed=stdin)(| |)\n"
    "from dsl import mylang\n"
    "__main__:\n"
    "\t@printf 'in_all=%s imported=[%s]\\n' '$(filter mylang,$(dsl.__all__))' '$(mylang.__mro__)'\n",
  )
  out = p.stdout + p.stderr
  assert p.returncode == 0, out
  assert "in_all=mylang" in out, out
  assert "imported=[Callable Materializable cmk.Fragment dsl.mylang]" in out, out
