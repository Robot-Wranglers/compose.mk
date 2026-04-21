"""Tests for the generic banana-bracket block constructor `NAME(| .. |)`.

A "native, generic declare": `NAME(| body |)` lowers the body to `define NAME .. endef`
and then applies a constructor named by a LEADING dotpath
(`declare channel inbox(| .. |)` == `$(call declare.channel, def=inbox)`).

- leading dotpath -> parse-time declaration `$(call C, def=NAME <with>)` (registers a receiver)
- `using <kw>`    -> kwargs threaded to the prefix constructor
- `with <kw>`     -> verbatim POSTFIX-treatment kwargs (commutative trailer)

The trailing `as C` / `as! C` clauses are GONE: an `as`/`as!` word is now swept into the
postfix-treatment list and fails as an unknown target (a generic postfix error).

The delimiter is chosen so an inline Idris idiom-bracket `(| f a b |)` in a body passes
through verbatim: the open needs a leading NAME word, the multi-line close is `|)` ALONE
on its line.
"""

import pytest

pytestmark = pytest.mark.compiler


# --- GRAMMAR-sync guard: banana-opener recognition across stages -------------
# The banana-opener grammar is consumed by two awk stages -- `dedent` (strips the body
# indent to col-0) and `sugar` (lowers the block).  They used to hand-copy the pattern and
# drifted (the `*(|` dissolve prefix reached sugar but not dedent), so a tab-indented body
# survived un-dedented -> "recipe commences before first target".  It is now defined once
# (`lang.rex.banana.open.*`, injected into both).  This guard feeds every opener prefix form with a
# tab-indented body and asserts the body lands at column 0 -- i.e. that both stages agree.
# A new opener form that updates only one stage fails here.
_OPENER_FORMS = [
  ("named", "greet(|\n\ta=1\n\tb=2\n|)\n"),
  ("ctor_path", "declare greet(|\n\ta=1\n\tb=2\n|)\n"),
  ("assign_eq", "N = (|\n\ta=1\n\tb=2\n|)\n"),
  ("assign_cook", "N := (|\n\ta=1\n\tb=2\n|)\n"),
  ("star_dissolve", "*(|\n\ta=1\n\tb=2\n|)\n"),
  ("cooked_bracket", "greet[|\n\ta=1\n\tb=2\n|]\n"),
]


@pytest.mark.parametrize("label,src", _OPENER_FORMS, ids=[f[0] for f in _OPENER_FORMS])
def test_opener_dedents_tab_body(ir, label, src):
  out = ir(src)
  assert "a=1" in out and "b=2" in out, f"{label}: body missing (opener not recognized)"
  assert "\ta=1" not in out, f"{label}: body NOT dedented -- dedent stage missed this opener"
  assert "\tb=2" not in out, f"{label}: body NOT dedented -- dedent stage missed this opener"


# --- trailing `as` declaration form -----------------------------------------


def test_trailing_as_removed(ir):
  # the trailing `as C` clause was REMOVED -- the constructor moves to the
  # prefix (see test_leading_path).  A trailing `as` is now swept into the
  # postfix-treatment list and fails as an unknown target.
  out = ir("greet(|\n    echo hi\n|) as code.unbound\n")
  assert "$(error" in out and "postfix treatment" in out and "unknown target" in out


def test_oneliner(ir):
  out = ir("code.unbound one(| echo hi |)\n")
  assert "define one" in out and "echo hi" in out
  assert "$(call code.unbound, def=one)" in out


def test_using_kwargs(ir):
  # `using <kw>` threads args to the prefix constructor (the old `as C with K`).
  out = ir("code.unbound r(|\n    x\n|) using img=alpine\n")
  assert "$(call code.unbound, def=r img=alpine)" in out


def test_paren_kwargs(ir):
  # `NAME(k=v)[| .. |]` -- kwargs on the name, the native front-form of the `using k=v` trailer.
  out = ir("code.unbound r(img=alpine)[|\n    x\n|]\n")
  assert "$(call code.unbound, def=r img=alpine)" in out


def test_paren_kwargs_equivalent_to_using(ir):
  # the paren form and the `using` trailer lower to the same constructor call.
  a = ir("code.unbound r(img=alpine)[|\n    x\n|]\n")
  b = ir("code.unbound r(|\n    x\n|) using img=alpine\n")
  assert "$(call code.unbound, def=r img=alpine)" in a
  assert "$(call code.unbound, def=r img=alpine)" in b


def test_paren_kwargs_without_prefix_errors(ir):
  # kwargs on the name with NO prefix constructor is the same orphan error as `using`.
  out = ir("r(img=alpine)[|\n    x\n|]\n")
  assert "$(error" in out and "PREFIX" in out


def test_paren_banana_not_kwargs(ir):
  # a normal `NAME(| body |)` is NOT mistaken for kwargs -- the `(|` opens a banana.
  out = ir("code.unbound r(|\n    x\n|)\n")
  assert "$(call code.unbound, def=r)" in out and "define r" in out


def test_metaclass_reflection(tmp_path):
  # `umbrella=1` is a metaclass kwarg -- the KIND records it via reflection: __metaclass__ (the
  # builder), __mcls_kwargs__ (the kwargs), __mcls_mint_ns__ (the resolved namespace, self here).  On
  # a constructor, umbrella is sugar the surface verb lowers to `ns=.`, so both appear in the kwargs.
  # A plain constructor stamps the builder with empty kwargs/ns.
  import subprocess
  from pathlib import Path
  repo = Path(__file__).resolve().parent.parent
  src = tmp_path / "mcls.cmk"
  src.write_text(
    "open cmk\n"
    "constructor color(umbrella=1)[|\n  ${self}.hex ?= 0\n|]\n"
    "constructor plain[|\n  ${self}.hex ?= 0\n|]\n"
    "show:; @printf 'C:%s/%s/%s P:%s/%s/%s\\n' "
    "'${color.__metaclass__}' '${color.__mcls_kwargs__}' '${color.__mcls_mint_ns__}' "
    "'${plain.__metaclass__}' '${plain.__mcls_kwargs__}' '${plain.__mcls_mint_ns__}'\n"
    "__main__: show\n"
  )
  r = subprocess.run(
    [str(repo / "compose.mk"), "cmk", "run", str(src), "show"],
    cwd=str(repo), capture_output=True, text=True, timeout=90,
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "C:constructor/umbrella=1 ns=./color" in out
  assert "P:constructor//" in out


def test_with_without_postfix_errors(ir):
  # `with <kw>` are POSTFIX-treatment args; with no postfix they are orphaned.
  out = ir("r(|\n    x\n|) with img=alpine\n")
  assert "$(error" in out and "`with`" in out and "POSTFIX" in out


# --- leading constructor-path (stronger prefix-absorption) -------------------


def test_leading_path(ir):
  out = ir("code unbound two(|\n    echo two\n|)\n")
  assert "define two" in out
  assert "$(call code.unbound, def=two)" in out


def test_leading_path_with_using(ir):
  out = ir("declare channel inbox(| |) using init_data=seed\n")
  assert "$(call declare.channel, def=inbox init_data=seed)" in out


def test_leading_path_plus_trailing_as_errors(ir):
  # a trailing `as` is gone; even with a leading path present, the `as` word is
  # swept into the postfix-treatment list and fails as an unknown target.
  out = ir("declare channel dup(|\n    x\n|) as code.unbound\n")
  assert "$(error" in out and "postfix treatment" in out and "unknown target" in out


# --- the `as!`/`as` clause is gone ------------------------------------------


def test_runtime_bang_removed(ir):
  # the runtime `as! C` form was removed along with `as`.  The `as!` word is now
  # swept into the postfix-treatment list and fails as an unknown target.
  out = ir("run(|\n    echo x\n|) as! docker_context\n")
  assert "$(error" in out and "postfix treatment" in out and "unknown target" in out


# --- Idris idiom-bracket collision-safety -----------------------------------


def test_idris_embed_passthrough(ir):
  # the inner `(| (+) (Just 1) (Just 2) |)` must survive byte-for-byte inside the body,
  # and the block must close on the `|)`-alone line, not the mid-line one.
  out = ir(
    "code.unbound demo(|\n    (| (+) (Just 1) (Just 2) |)   -- Just 3\n|)\n",
  )
  assert "(| (+) (Just 1) (Just 2) |)   -- Just 3" in out
  assert "$(call code.unbound, def=demo)" in out


# --- receiver registration ---------------------------------------------------


def test_registers_receiver(ir):
  out = ir("declare.channel inbox(| |)\nx:\n\tinbox.push(foo=bar)\n")
  assert "${make} inbox.push/foo=bar" in out


# --- zero-constructor degenerate form ---------------------------------------


def test_bare_is_plain_define(ir):
  # no leading path and no trailing as => just the define, no `$(call)`.
  out = ir("plain(|\n    hello\n|)\n")
  assert out.defines() == ["plain"]  # just the define...
  assert not out.calls()  # ...no constructor $(call) emitted


# --- `[stream]` trailer: comptime capture -----------------------------------
# `NAME(| filter |)[S]` runs the block as a shell filter over S DURING the parse and
# binds the block's name to the result: define + `NAME := $(shell S | bash <block-file>)`.
# `[...]` here means STREAM (not kwargs -- those live on `with`/`(args)`); it is mutually
# exclusive with a constructor.  (`⬥NAME` -> a real file via the later blockref stage.)


def test_stream_trailer_filter(ir):
  out = ir("up(| tr a-z A-Z |)[echo hi]\n")
  assert "define up" in out
  assert "up := $(shell echo hi | bash $(call _mk.def.tmpfile, up))" in out


def test_stream_trailer_producer_empty(ir):
  # `[]` -- an empty stream: a producer block, run with NO input (no leading pipe).
  out = ir("gen(| printf X |)[]\n")
  assert "gen := $(shell bash $(call _mk.def.tmpfile, gen))" in out


def test_stream_trailer_excludes_constructor(ir):
  # a stream-filter block is a comptime value; it cannot also be constructed.
  out = ir("scaffold foo(| b |)[echo hi]\n")
  assert "$(error" in out and "[stream]" in out and "constructor" in out


def test_bare_block_is_not_comptime(ir):
  # regression guard: a bare block (NO bracket) must stay a plain define, never a
  # comptime `$(shell)` run (the `[]` vs no-bracket distinction).
  out = ir("plain(| body |)\n")
  assert "$(shell" not in out
  assert "plain :=" not in out


# --- `(args)` trailer: block as a make macro, POSITION-SENSITIVE ------------
# `NAME(| body |)(a,b)` applies the block as a make macro `$(call NAME,a,b)`, the
# dual of `[S]` (which runs it as a shell filter).  Position decides the form:
#   statement `NAME(|..|)(a,b)`      -> `$(eval $(call NAME,a,b))`  (codegen)
#   value     `X = NAME(|..|)(a,b)`  -> `X := $(call NAME,a,b)`     (capture)


def test_args_statement_is_codegen(ir):
  out = ir("component(| $(1).x:; @echo $(1) |)(auth)\n")
  assert "define component" in out
  assert "$(eval $(call component,auth))" in out


def test_args_value_is_capture(ir):
  out = ir("G = greeter(| hi $(1) |)(world)\n")
  assert "G := $(call greeter,world)" in out


def test_args_excludes_constructor(ir):
  out = ir("declare foo(| x |)(a)\n")
  assert "$(error" in out and "(args)" in out and "constructor" in out


def test_stream_value_captures_into_lhs(ir):
  # `X = NAME(|..|)[S]` captures into X and LEAVES the block define intact.
  out = ir("N = up(| tr a-z A-Z |)[echo hey]\n")
  assert "define up" in out
  assert "N := $(shell echo hey | bash $(call _mk.def.tmpfile, up))" in out


def test_ordinary_assignments_untouched(ir):
  # CRITICAL: the LHS-prefix opener must not touch normal make assignments that
  # have no `(|` block.  (`Z = a(b)c` has parens but no banana.)
  out = ir("X = foo bar\nY := $(shell echo hi)\nZ = a(b)c\n")
  assert "X = foo bar" in out
  assert "Y := $(shell echo hi)" in out
  assert "Z = a(b)c" in out


# --- lambda-lift SPIKE: anonymous in-recipe `(| body |)(kwargs)` --------------
def test_recipe_ctor_env_channel(ir):
  # `{k=v}` on a ctor recipe idiom (`<machine>(| body |){k=v}`) -> `k='v'` env prefix on the
  # machine's `.__call__`, run over the body blockref.
  out = ir("d7:\n\thost.native.sh(| echo hi |){cmd=pwd}\n")
  assert "define __lambda_" in out and "echo hi" in out
  assert "cmd=pwd $(if " in out and "$(call host.native.sh.__call__," in out  # machine -> kind-call branch


def test_recipe_ctor_args_channel(ir):
  # `(a,b)` on a ctor recipe idiom -> positional args after the body blockref.
  out = ir("d:\n\thost.native.sh(| body |)(build,test)\n")
  assert "$(call host.native.sh.__call__," in out and " build test)" in out


def test_recipe_ctor_env_and_args_dont_collide(ir):
  # DISTINCT brackets, order-free: `{e=1}(a,b)` == `(a,b){e=1}`; env prefix + positional args.
  for src in (
    "d:\n\thost.native.sh(| body |){e=1}(a,b)\n",
    "d:\n\thost.native.sh(| body |)(a,b){e=1}\n",
  ):
    out = ir(src)
    assert "e=1 $(if " in out and "$(call host.native.sh.__call__," in out and " a b)" in out


def test_lambda_lift_skips_named_block(ir):
  # a NAMED block with args is the module-macro form -- not lifted.
  out = ir("component(| x |)(auth)\n")
  assert "__lambda_" not in out
  assert "$(eval $(call component,auth))" in out


def test_lambda_lift_skips_idiom_in_define(ir):
  # `(| .. |)` inside a user define (e.g. an Idris idiom) is never lifted (defskip).
  out = ir("code.unbound demo(|\n    (| f a b |)(x)\n|)\n")
  assert "__lambda_" not in out
  assert "(| f a b |)(x)" in out


def test_recipe_ctor_hoists_body_to_module_define(ir):
  # the block is hoisted to a module `define __lambda_N` carrying the body verbatim; the recipe
  # keeps a `.__call__` receiver over the body (routed as a blockref).
  out = ir("d:\n\thost.native.sh(| FROM alpine |){cmd=pwd}\n")
  assert "cmd=pwd $(if " in out and "$(call host.native.sh.__call__," in out  # env + machine kind-call
  assert "define __lambda_" in out and "FROM alpine" in out  # body lifted to a define


def test_recipe_ctor_env_only_no_trailing_args(ir):
  # `{e=v}` alone -> env prefix + `.__call__(blockref)`, no positional args.
  out = ir("d:\n\thost.native.sh(| body |){e=1}\n")
  assert "e=1 $(if " in out and "$(call host.native.sh.__call__," in out


def test_recipe_anonymous_ctor_banana_runs(tmp_path):
  # BEHAVIORAL: the `demos/cmk/banana-recipes.cmk` `demo.inlined` form -- an ANONYMOUS recipe-scope
  # ctor banana `dsl.jqlang(| .. |).locals()` (name left of `(|` is a CTOR, instance gensym'd,
  # nothing left in scope) folds the target-locals into JSON.  Pins that the left name is treated
  # as a ctor (gensym + `.method()`), not a named `define`.  Needs jq + the target_locals pragma.
  import subprocess
  from pathlib import Path
  repo = Path(__file__).resolve().parent.parent
  src = tmp_path / "recbanana.cmk"
  src.write_text(
    "# cmk_pragma ::: { \"target_locals\": true } :::\n"
    "from cmk import dsl\n"
    "demo:\n"
    "\tuser <- printf alice\n"
    "\trole=admin\n"
    "\tready=true\n"
    "\tdsl.jqlang(| { vars: ., total: (. | length) } |).locals()\n"
    "__main__: demo\n"
  )
  r = subprocess.run(
    [str(repo / "compose.mk"), "cmk", "run", str(src)],
    cwd=str(repo), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=90,
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert '"user": "alice"' in r.stdout, out
  assert '"role": "admin"' in r.stdout, out
  assert '"total": 3' in r.stdout, out


def test_recipe_bare_ctor_banana_is_gensym_not_shadow(tmp_path):
  # A BARE recipe banana `NAME(| body |)` (no trailer/capture) is the ctor gensym'd, NOT a `define NAME`
  # (which used to shadow the ctor + orphan sibling recipe lines with a parse error).  Sugar hands the
  # truly-bare recipe form to lambdalift (its look-ahead still folds dot-chains -- see
  # test_dot_chain_split_cmk).  A ctor gensym is an inert no-op; a bare form beside an invoked one must
  # coexist (the ` && ` recipe join is `:`-safe), and the ctor stays usable afterward.
  import subprocess
  from pathlib import Path
  repo = Path(__file__).resolve().parent.parent
  src = tmp_path / "bare.cmk"
  src.write_text(
    "from cmk import dsl\n"
    "dsl bclang(entrypoint=bc feed=stdin)(| |)\n"
    "bclang area(| 1 + 1 |)\n"
    "t:\n"
    "\tbclang(| 6 + 6 |)\n"            # bare ctor -> inert no-op (not `define bclang`)
    "\tbclang(| 7 + 7 |)()\n"          # invoked sibling -> must still run (14) despite the bare line
    "\tarea()\n"                       # the ctor is unshadowed -> named instance still works (2)
    "__main__: t\n"
  )
  r = subprocess.run(
    [str(repo / "compose.mk"), "cmk", "run", str(src)],
    cwd=str(repo), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=90,
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "recipe commences" not in out and "missing separator" not in out, out
  assert "14" in r.stdout, out                      # the invoked sibling ran
  assert "2" in r.stdout, out                       # area() still works (ctor unshadowed)


def _run_machine_form(tmp_path, recipe_line):
  # helper: run one recipe line whose head is the `host.native.sh` machine, headless.
  import subprocess
  from pathlib import Path
  repo = Path(__file__).resolve().parent.parent
  src = tmp_path / "mform.cmk"
  src.write_text("from cmk import host\n__main__:\n\t" + recipe_line + "\n")
  return subprocess.run(
    [str(repo / "compose.mk"), "cmk", "run", str(src)],
    cwd=str(repo), stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=90,
  )


# The three recipe-level machine callforms.  A machine is-a Runnable (not a constructor-kind), so a
# banana body is fed to its `.__call__` and RUN in the machine (execute-on-apply); the paren-args form
# is a plain callform on the receiver.


def test_recipe_machine_banana_bare_runs(tmp_path):
  # `machine(| body |)` -- bare banana, no trailer: runs the body in the machine (execute-on-apply,
  # via the kind-call), since a machine is not a constructor-kind.
  r = _run_machine_form(tmp_path, "host.native.sh(| echo FORM_BARE |)")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "FORM_BARE" in r.stdout, out


def test_recipe_machine_banana_invoke_runs(tmp_path):
  # `machine(| body |)()` -- banana + invoke trailer: runs the body in the machine (same kind-call
  # path as the bare form; the `()` is redundant for a machine but valid).
  r = _run_machine_form(tmp_path, "host.native.sh(| echo FORM_INVOKE |)()")
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "FORM_INVOKE" in r.stdout, out


@pytest.mark.xfail(
  reason="`machine(args)` (paren-args callform on a machine) is broken in TWO layers.  (1) RECOGNITION: "
  "a CORE machine imported via `from cmk import host` is not in the source-scanned RECEIVERS list "
  "(lang.parse.scan.receivers greps the SOURCE for declarations -- def=/as/banana/capture/goal -- and "
  "host.native.sh is never one), so the callform stays verbatim and hits the shell.  Seeding RECEIVERS "
  "fixes recognition (proven: it then lowers to `$(call host.native.sh.__call__,args)`).  (2) SEMANTICS: "
  "even recognized, `.__call__` builds `<entrypoint> <args>` (`sh whoami`), treating args as a script "
  "FILE not a command -> `cannot open whoami`.  A working form needs both.  Comma-independent: "
  "single-arg `host.native.sh(whoami)` fails identically.  (Banana forms work: lambdalift keys on `(|`.)"
)
@pytest.mark.parametrize("line", ["host.native.sh(whoami)", "host.native.sh(-c, echo FORM_ARGS)"])
def test_recipe_machine_paren_args_callform(tmp_path, line):
  # `machine(args)` -- EXPECTED: a callform on the machine receiver running the entrypoint with args.
  # Both the no-comma single-arg form and the comma form fail the same way (receiver not registered).
  r = _run_machine_form(tmp_path, line)
  out = r.stdout + r.stderr
  assert r.returncode == 0, out


def test_anon_callform_is_reserved(ir):
  # an anonymous banana has only a string algebra, no callforms: a bare `(| .. |){env}` / `(args)`
  # / `[| .. |]{env}` (no ctor, no `in`) is RESERVED -> a make `$(error)` carrying the hierarchical
  # code, which fires at validate/run (rc!=0).
  for src in ("d:\n\t(| body |){e=1}\n", "d:\n\t(| body |)(a,b)\n", "d:\n\t[| body |]{e=1}\n"):
    out = ir(src)
    assert "$(error" in out and "NotImplemented/Grammar/anon-callform" in out


# --- `in <ambient>`: uniform dispatch, no bare-image string-sniff -------------
def test_lambda_in_bare_ambient(ir):
  # `in <name>` (host machine / named instance / compose service) routes through the
  # ambient's own `<name>/%` dispatch via `_cmk.host.machine` -- one uniform path.
  out = ir("d:\n\t(| echo hi |) in box\n")
  assert "${make} $(call _cmk.host.machine,box)/__lambda_" in out


def test_lambda_in_inline_container(ir):
  # `in container(| img=X entrypoint=Y |)` mints an ANONYMOUS ambient: the ctor body is
  # hoisted to a `define __ambient_N`, `$(call container, def=__ambient_N)` is hoisted to
  # module scope, and the lambda dispatches into it by name (reuses the anon-instance parser).
  out = ir(
    "open cmk\nd:\n\t(| echo hi |) in container(| img=alpine:3.21 entrypoint=sh |)\n",
  )
  assert "define __ambient_" in out
  assert "img=alpine:3.21 entrypoint=sh" in out
  assert "$(call container, def=__ambient_" in out
  assert "${make} $(call _cmk.host.machine,__ambient_" in out  # dispatch by the minted name


@pytest.mark.xfail(
  reason="quoted-kwarg fix (build_call ␟-sentinel, compose.mk ~10223) covers the leading-paren "
  "decl form `container(kwargs)(| |)` but NOT the inline anonymous `in container(| .. |)` form.  "
  "The inline body is hoisted to `define __ambient_N` by the lambda-lift ambient path "
  "(_lam_trailer), which BYPASSES build_call, so a quoted spaced `cmd='a b'` is emitted RAW and "
  "truncates to `'a` when the machine capture reads it via mk.kwargs.get.  Left intentionally "
  "unmigrated: the paren form here collides with the `in name(argv)` dispatch grammar (see the "
  "kwargs-paren-migration plan).  DESIRED = the inline body is ␟-sentinelized like the paren form.",
  strict=False,
)
def test_lambda_in_inline_container_quoted_cmd_unsentineled(ir):
  # a quoted spaced cmd in the INLINE anonymous ambient should survive (be ␟-sentinelized in the
  # hoisted `define __ambient_N`, like the paren decl form).  It currently passes through RAW
  # (`cmd='a b'`) and truncates at capture -- the sentinel (␟) never reaches this path.
  out = ir("open cmk\nd:\n\t(| echo hi |) in container(| img=alpine:3.21 cmd='a b' |)\n")
  assert "cmd=a␟b" in out


def test_lambda_in_bare_image_errors(ir):
  # a bare image (has `:`/`/`) is NOT an ambient -- there is no string-sniff shortcut; it is a
  # compile error that points at the `in container(| img=.. |)` wrapping.
  out = ir("d:\n\t(| echo hi |) in debian:bookworm-slim\n")
  assert "a bare image is not an ambient" in out
  assert "in container(| img=debian:bookworm-slim" in out


# --- multi-body composition: `[ctor] NAME(| A |)(| B |)..` --------------------
# N block bodies to a constructor (currying): body1 = def=NAME, extras = def2=/def3=
# (gensym'd NAME__2, NAME__3).  Needs a constructor.  The `(|`-vs-`(` shape keeps it
# distinct from an `(args)` trailer -- no collision.


def test_multibody_two_with_ctor(ir):
  out = ir("declare X(|A|)(|B|)\n")
  assert "define X__2" in out and "$(call declare, def=X def2=X__2)" in out


def test_multibody_three(ir):
  out = ir("declare X(|A|)(|B|)(|C|)\n")
  assert "define X__3" in out
  assert "$(call declare, def=X def2=X__2 def3=X__3)" in out


def test_multibody_multiline(ir):
  out = ir("declare X(|\n  a1\n|)(|\n  b1\n|)\n")
  assert "define X\n" in out and "a1" in out
  assert "define X__2\n" in out and "b1" in out
  assert "$(call declare, def=X def2=X__2)" in out


def test_multibody_with_using(ir):
  out = ir("declare X(|A|)(|B|) using cmd=pwd\n")
  assert "$(call declare, def=X def2=X__2 cmd=pwd)" in out


def test_compact_delimiters_multiline(ir):
  # commons: a multi-line block whose body abuts the delimiters (`(|a1` .. `b1|)`)
  # lowers identically to the canonical form (`(|` / `|)` on their own lines).  The
  # opener buffers its inline body-head; a trailing close on a content line closes.
  compact = ir("greet(|a1\nb1|)\n")
  assert "define greet\na1\nb1\nendef" in compact
  canonical = ir("greet(|\na1\nb1\n|)\n")
  assert "define greet\na1\nb1\nendef" in canonical


def test_compact_close_only_when_trailing(ir):
  # A literal `|)` mid-line (stuff after it) is not a close -- it stays verbatim body,
  # so a foreign/shell body containing `|)` is not truncated.
  out = ir('greet(|\necho "a|)b"\n|)\n')
  assert 'echo "a|)b"' in out and "define greet" in out


def test_multibody_needs_constructor(ir):
  out = ir("X(|A|)(|B|)\n")
  assert "$(error" in out and "multi-body" in out


def test_args_not_confused_with_multibody(ir):
  # `(a,b)` (opens `(`, not `(|`) is an args trailer, not a second body.
  out = ir("X(|A|)(a,b)\n")
  assert "__2" not in out
  assert "$(eval $(call X,a,b))" in out


def test_plus_is_explicit_composition(ir):
  # `+` between blocks is the explicit spelling of default adjacency composition:
  # `(| A |) + (| B |)` produces the SAME operand list as `(| A |)(| B |)`.
  adjacency = ir("declare X(|A|)(|B|)\n")
  plus = ir("declare X(|A|) + (|B|)\n")
  assert "define X__2" in plus
  assert "$(call declare, def=X def2=X__2)" in plus  # same as adjacency
  # the `+` is pure surface sugar -- the lowered call line is identical
  assert "$(call declare, def=X def2=X__2)" in adjacency


def test_plus_composition_three(ir):
  out = ir("declare X(|A|) + (|B|) + (|C|)\n")
  assert "$(call declare, def=X def2=X__2 def3=X__3)" in out


def test_plus_composition_multiline_bodies(ir):
  # `+` also joins MULTI-LINE bodies when the `+` sits on the close line
  # (`|) + (|`), same as bare adjacency `|)(|`.  A `+` on its OWN line is not
  # a join (no newline-spanning operator) -- that stays out of scope.
  out = ir("declare X(|\n  a1\n|) + (|\n  b1\n|)\n")
  assert "define X\n" in out and "a1" in out
  assert "define X__2\n" in out and "b1" in out
  assert "$(call declare, def=X def2=X__2)" in out


# --- `cooked` / `cooked_deeply` postfix: compile the block interior ----------
# A bare block body is VERBATIM.  A trailing `cooked` runs the interior through
# the full cmk compiler BEFORE it becomes a `define`; `cooked_deeply` also
# DEEP-cooks any nested banana in the body.  The postfix composes with a prefix
# constructor (`declare.X NAME(| .. |) cooked`).


def test_cooked_postfix_lowers_interior(ir):
  raw = ir("r(| a:; cmk.log(x) |)\n")
  assert "cmk.log(x)" in raw and "$(call log" not in raw
  ck = ir("c(| a:; cmk.log(x) |) cooked\n")
  assert "$(call log,x)" in ck  # LOWERED by cooked


def test_cooked_postfix_composes_with_prefix_ctor(ir):
  # a `cooked` postfix and a prefix constructor compose: the body cooks AND the
  # ctor runs.  (Replaces the removed `.cooked`-suffix-implies-postfix shortcut.)
  out = ir("declare.macro _hi(| a:; cmk.log(x) |) cooked\n")
  assert "$(call log,x)" in out  # body cooked
  assert "$(call declare.macro, def=_hi)" in out  # ctor still runs


def test_dotcooked_ctor_is_not_special(ir):
  # the `.cooked` ctor-suffix convention was REMOVED: `ctor.cooked` is now just a
  # constructor literally NAMED `ctor.cooked`, and the body is not cooked.
  out = ir("declare.macro.cooked _hi(| a:; cmk.log(x) |)\n")
  assert "cmk.log(x)" in out and "$(call log" not in out  # RAW
  assert "$(call declare.macro.cooked, def=_hi)" in out  # literal ctor name


def test_cooked_body_preserves_backslash_continuation(ir):
  # regression: a `\`-continued recipe line inside a COOKED banana used to be
  # dropped by the `indent` stage -- it only treated define/endef as body
  # boundaries, not the `⟅`/`⟆` cook sentinels, so the continuation's tab+space
  # indent tripped the space-normalizer.  It must survive verbatim, like a real
  # define body.  (A RAW banana never hit this -- its body is passed through.)
  src = "c(|\n${self}:\n\t{ echo A; echo B; } \\\n\t  | cat\n|) cooked\n"
  out = ir(src)
  assert "{ echo A; echo B; } \\" in out  # the `\`-terminated line survives
  assert "| cat" in out  # ...and its continuation is not dropped


def test_cooked_deeply_deep_cooks_nested(ir):
  # `cooked_deeply` force-cooks a RAW nested banana too (deep cook).
  out = ir(
    "outer(|\n  top:; cmk.log(o)\n  inner(|\n    deep:; cmk.log(i)\n  |)\n|) cooked_deeply\n",
  )
  assert "define inner" in out  # nested banana -> nested define
  assert "$(call log,o)" in out  # outer body lowered
  assert "$(call log,i)" in out  # inner body lowered too (deep)


def test_bang_shallow_cooks_oneliner(ir):
  # unary `!` postfix cooks a RAW `(| |)` body -- shallow: this body lowers.
  raw = ir("c(| a:; cmk.log(x) |)\n")
  assert "cmk.log(x)" in raw and "$(call log" not in raw  # verbatim
  out = ir("c(| a:; cmk.log(x) |)!\n")
  assert "$(call log,x)" in out  # `!` cooked it


def test_bang_is_shallow_not_deep(ir):
  # `!` = SHALLOW cook (quasiquote-level respecting): lower THIS body's callforms,
  # but a nested raw `(| |)` stays raw -- the exact opposite of `cooked_deeply`,
  # which forces the nested one to cook too (test_cooked_deeply_deep_cooks_nested).
  src = "outer(|\n  top:; cmk.log(o)\n  inner(|\n    deep:; cmk.log(i)\n  |)\n|)!\n"
  out = ir(src)
  assert "$(call log,o)" in out  # outer body cooked
  assert "define inner" in out  # nested banana -> nested define
  assert "cmk.log(i)" in out and "$(call log,i)" not in out  # inner stays RAW


def test_bang_downgrades_deep_bracket(ir):
  # `[| |]!` -- a `!` on a deep bracket downgrades it to shallow: nested stays raw.
  src = "outer[|\n  top:; cmk.log(o)\n  inner(|\n    deep:; cmk.log(i)\n  |)\n|]!\n"
  out = ir(src)
  assert "$(call log,o)" in out  # outer still cooked
  assert "cmk.log(i)" in out and "$(call log,i)" not in out  # but nested NOT (shallow)


# --- recipe `+` / adjacency: value-concatenation (capture) only ------------------
# `+`/adjacency compose recipe machines: under a `<-` capture the outputs are
# CONCATENATED ("a then b", value monoid).  A bare (uncaptured) concat has no
# execution context, so it is an inert string and an error on its own recipe line.
# `!` (shallow cook) stays module-level, and `+`/multi-body COMBINED WITH a lambda
# `(args)` trailer is undefined -> error.


@pytest.mark.parametrize(
  "recipe",
  ["x <- (| echo a |) + (| echo b |)", "x <- (| echo a |)(| echo b |)"],
  ids=["plus", "adjacency"],
)
def test_recipe_capture_plus_concatenates(ir, recipe):
  # both bodies hoist + the capture runs them in sequence into one backtick.
  out = ir("foo:\n\t%s\n" % recipe)
  assert "define __cap_" in out
  assert out.count("__cap_") >= 4  # two defines + two run-refs
  assert ";" in out  # sequential run inside the capture
  assert "$(error" not in out


def test_recipe_capture_plus_three(ir):
  out = ir("foo:\n\tx <- (| echo a |) + (| echo b |) + (| echo c |)\n")
  assert out.count("define __cap_") == 3


def test_recipe_uncaptured_plus_errors(ir):
  # no capture, no machine -> a bare `+` concat is an inert string, not runnable: error, and
  # nothing is lowered to run (no `. <(..)`, no hoisted effect defines).
  out = ir("foo:\n\t(| echo a |) + (| echo b |)\n")
  assert "$(error" in out and "inert string-concat" in out
  assert ". <(" not in out and "define __eff_" not in out


@pytest.mark.parametrize(
  "recipe",
  ["x <- (| echo hi |) | (| tr a-z A-Z |)", "(| echo hi |) | (| cat -n |)"],
  ids=["capture", "uncaptured"],
)
def test_recipe_pipe_is_undefined_on_raw(ir, recipe):
  # raw `|` (pipe) is UNDEFINED between unconstructed bananas -- pipe is a typed/data-flow op
  # owned by a KIND (jqlang etc.), not part of a raw banana's string-algebra.  reject-by-default
  # (no per-operator blocklist): inline the pipe in one block, or type the operands.  `+`/juxt is
  # the only defined raw operator.
  out = ir("foo:\n\t%s\n" % recipe)
  assert "$(error" in out and "undefined operator" in out
  assert "| bash" not in out


def test_recipe_pipe_three_stage_is_undefined(ir):
  # a multi-stage raw pipe is likewise undefined -- rejected, no `bash` pipeline lowered.
  out = ir("foo:\n\tx <- (|a|) | (|b|) | (|c|)\n")
  assert "$(error" in out and "undefined operator" in out
  assert "define __cap_" not in out


def test_recipe_plus_sequences_not_pipes(ir):
  # `+` stays sequence (`;`), distinct from `|` (pipe).
  out = ir("foo:\n\tx <- (| echo a |) + (| echo b |)\n")
  assert "; bash" in out and "| bash" not in out


def test_recipe_juxtaposition_errors_like_plus(ir):
  # bare juxtaposition `(| a |)(| b |)` = `+`: both are inert string-concat, so both error
  # uncaptured (nothing hoisted to run).
  plus = ir("foo:\n\t(| echo a |) + (| echo b |)\n")
  juxt = ir("foo:\n\t(| echo a |)(| echo b |)\n")
  for out in (plus, juxt):
    assert "$(error" in out and "inert string-concat" in out
    assert "define __eff_" not in out


def test_recipe_bare_lambda_errors(ir):
  # a bare single-line `(| body |)` with no execution context is an inert string, not runnable:
  # error, and nothing is hoisted or sourced (no `. <(..)`).
  out = ir("foo:\n\t(| echo solo |)\n")
  assert "$(error" in out and "inert string" in out
  assert ". <(" not in out and "define __lambda_" not in out


def test_recipe_capture_bang_still_errors(ir):
  # `!` (shallow cook) remains module-level only, even under capture.
  out = ir("foo:\n\tx <- (| echo a |)!\n")
  assert "$(error" in out and "recipe capture" in out


@pytest.mark.parametrize(
  "recipe",
  ["(| echo a |) + (| echo b |)(x)", "(| cmk.log(x) |)!(x)", "(| echo a |)(| echo b |)(x)"],
  ids=["plus", "bang", "multibody"],
)
def test_recipe_lambda_trailer_with_operator_errors(ir, recipe):
  # `+`/`!`/multi-body COMBINED WITH a lambda `(args)` trailer is undefined.
  out = ir("foo:\n\t%s\n" % recipe)
  assert "$(error" in out and "recipe lambda" in out


def test_recipe_forms_still_lower_after_guards(ir):
  # regression: single-body recipe forms are untouched by the peel.
  cap = ir("foo:\n\tx <- (| echo hi |)\n")
  assert "x=`bash" in cap and "define __cap" in cap
  cooked = ir("foo:\n\tx <- [| cmk.log(hi) |]\n")
  assert "$(call log,hi)" in cooked  # cooked capture still cooks
  lam = ir("foo:\n\thost.native.sh(| echo hi |)(alpine)\n")
  assert "__lambda" in lam and "host.native.sh.__call__" in lam


# --- postfix TARGET treatment: a non-builtin postfix is a target the body is
# piped through at COMPILE time (`./compose.mk <target>`).  `stream.echo` is the
# stdlib identity filter; a missing target falls back to the raw body.


def test_postfix_target_treatment_round_trips(ir):
  # `cooked, stream.echo`: `cooked` (builtin) lowers the interior, then the body
  # is piped through the `stream.echo` target (identity) and taken back.
  out = ir("p(| a:; cmk.log(x) |) cooked, stream.echo\n")
  assert (
    "define p" in out and "endef" in out
  )  # valid define after the round-trip
  assert "$(call log,x)" in out  # cook ran; stream.echo preserved it


def test_postfix_unknown_target_is_compile_error(ir):
  # a treatment target that is missing / exits non-zero is a COMPILE error (the
  # shell-out happens at compile time), not a silent fallback.
  out = ir("p(| a:; echo hi |) no.such.target.xyz\n")
  assert "$(error" in out and "no.such.target.xyz" in out
  assert (
    "define p" not in out
  )  # the block is not emitted on a failed treatment


# --- alternate bracket families: `[| .. |]` deep-cook + `{| .. |}` pragma ------
# `[|`/`{|` are FIRST-CLASS banana openers in the sugar parser (a per-frame cook
# flag, fed through the same postfix-treatment path a trailing `cooked_deeply`
# word takes): `[| .. |]` deep-cooks, `{| .. |}` -> the treatment its
# `block_brackets` pragma entry configures. Literal brackets stay verbatim exactly
# where a `(|` banana is inert (define body, foreign-body importer banana).


def test_square_bracket_is_deep_cook(ir):
  # `NAME[| .. |]` cooks the interior, same as the `cooked_deeply` postfix word.
  out = ir("deploy[| a:; cmk.log(x) |]\n")
  assert "define deploy" in out
  assert (
    "$(call log,x)" in out and "cmk.log" not in out
  )  # cooked


def test_square_bracket_deep_cooks_nested(ir):
  # deep-cook reaches a nested (raw-looking) banana in the body.
  out = ir(
    "outer[|\n  top:; cmk.log(o)\n  inner(|\n    deep:; cmk.log(i)\n  |)\n|]\n",
  )
  assert "define inner" in out
  assert "$(call log,o)" in out and "$(call log,i)" in out


def test_bracket_guard_skips_verbatim_regions(ir):
  # `[|` is a first-class banana family now, so literal `[|`/`|]` survives exactly the
  # contexts where a `(|` banana is also inert: a hand-written `define` body, and a
  # foreign-body importer banana (fverb: import/docker/polyglot), whose body is verbatim.
  ind = ir("define D\nx = [| literal |]\nendef\ny:; @true\n")
  assert "[| literal |]" in ind  # define body untouched
  imp = ir("polyglot py demo(|\nx = [| literal |]\n|)\n")
  assert "[| literal |]" in imp  # foreign-body importer banana is verbatim
  # A PLAIN `(| .. |)` body is not verbatim: a nested banana (any bracket) is parsed as a
  # nested define -- the documented nesting feature, identical for `[|` and `(|`.
  nest_sq = ir("raw(|\n  q = [| literal |]\n|)\n")
  nest_rd = ir("raw(|\n  q = (| literal |)\n|)\n")
  assert (
    "define q" in nest_sq and "define q" in nest_rd
  )  # both nest the same way


def test_bracket_stream_trailer_still_parses(ir):
  # `NAME(| .. |)[S]` is a stream trailer, never mistaken for a `[|` open.
  out = ir("x=fmt(|[$(1)]|)[echo hi]\n")
  assert "$(shell echo hi |" in out  # stream form intact


def test_square_bracket_one_liner_with_ctor_and_trailer(ir):
  # one-liner `[| .. |]` with a prefix ctor and a `using` trailer: cooks, runs the
  # ctor, and preserves the trailer.
  out = ir("declare deploy[| a |] using k=v\n")
  assert "$(call declare, def=deploy" in out and "k=v" in out


def test_brace_bracket_pragma_treatment(ir):
  # `{| .. |}` routes through the treatment set by the block_brackets pragma.
  src = (
    '# cmk_pragma ::: {"block_brackets": ["{}=cooked_deeply"]} :::\n'
    "foo{| a:; cmk.log(x) |}\n"
  )
  out = ir(src)
  assert (
    "define foo" in out and "$(call log,x)" in out
  )  # cooked via pragma


def test_recipe_level_banana_capture(ir):
  # `LHS <- (| body |)` on a RECIPE line lifts the block to a module define and emits
  # a runtime shell capture (`LHS=`bash ⬥__cap_N``), so LHS is set when the recipe runs
  # -- not a parse-time make var like the module-level `X <- (| .. |)`.
  out = ir("d:\n\tval <- (| printf hi |)\n\t@echo $$val\n")
  assert "define __cap_" in out  # block hoisted to module scope
  assert (
    "val=`bash " in out
  )  # recipe-level shell capture (raw body run as bash)
  assert "val := $(shell" not in out  # NOT the module-level make assignment


def test_recipe_level_cooked_capture(ir):
  # `LHS <- [| body |]` COOKS the interior (callforms lower), then make-expands the
  # cooked define at recipe time (`LHS=`$(__cap_N)``) so `${make}`/`$(call ..)` resolve
  # and the result runs -- captured into the shell var.
  out = ir("d:\n\tval <- [| this.pong |]\npong:; @true\n")
  assert "val=`$(__cap_" in out  # make-expand the cooked define (not bash)
  assert "${make} pong" in out  # this.pong lowered inside the lifted define


def test_module_level_banana_capture_unchanged(ir):
  # a column-0 `X <- (| .. |)` stays the module (parse-time) capture.
  out = ir("X <- (| printf hi |)\ny:; @true\n")
  assert "X := $(shell bash " in out


def test_module_level_cooked_capture_is_compile_error(ir):
  # a column-0 `X <- [| .. |]` would shell a COOKED (`${make} ..`) body at PARSE time via
  # `:=` `$(shell ..)`, which re-parses -> recurses (a fork storm).  It must be a hard
  # compile error, not a silent `$(shell ..)`.  Cooked capture is a recipe-level form.
  out = ir("X <- [| this.foo(a) |]\ny:; @true\n")
  assert "$(error" in out and "cooked capture" in out
  assert (
    "X := $(shell" not in out
  )  # the dangerous parse-time shell must NOT be emitted


# --- orphan-arg guards: every modifier requires its processor ---------------


def test_using_without_prefix_errors(ir):
  out = ir("X(| a |) using k=v\n")
  assert "$(error" in out and "`using`" in out and "PREFIX" in out


def test_cooked_ignores_with_args(ir):
  # builtins like `cooked` accept (and ignore) `with` args -- no orphan error.
  out = ir("c(| a:; cmk.log(x) |) cooked with heat=high\n")
  assert "define c" in out
  assert "$(call log,x)" in out
  assert "$(error" not in out


# --- nested bananas: each becomes its own (possibly nested) define -----------


def test_nested_banana_is_nested_define(ir):
  out = ir(
    "outer(|\n  a:; @echo o\n  inner(|\n    b:; @echo i\n  |)\n|)\n",
  )
  assert "define outer" in out and "define inner" in out
  # the inner define is emitted INSIDE the outer one
  assert (
    out.index("define outer") < out.index("define inner") < out.index("endef")
  )


# --- banana-delimiter collision inside a body (surfaced by Ruby-in-graal) -----
# The lexer's banana-balance counter (.awk.cmk.dedent) counts every `(|`/`|)`
# SEQUENCE regardless of the opener grammar (an open "needs a leading NAME word",
# per this file's header) or guest string literals.  So a bare `(|`/`|)` inside a
# body collides.  Ruby blocks `{ |i| }` and logical `||` are UNAFFECTED (neither is
# a `(|`/`|)` sequence), so the graal demo's `p4` is fine -- this is the residual
# corner the demo's `|i|` avoidance was (over-)guarding against.
@pytest.mark.xfail(
  reason="banana-balance counter (.awk.cmk.dedent) is not guest-string- or opener-grammar-aware: it "
  "counts a bare `(|` inside a body (here space-preceded inside a shell/ruby string -- NOT a valid "
  "opener, which needs a leading NAME word) as a nested OPEN -> `unbalanced banana block`.  (A "
  "single-line body additionally closes early at any `|)`; the multi-line `|)`-alone-on-its-line rule "
  "protects `|)` mid-body but not `(|`.)  DESIRED = a `(|`/`|)` sequence inside a body passes through "
  "verbatim.  A fix makes the balance check honor the opener grammar / skip string literals -- a deep "
  "lexer change (see dont-modify-compiler-without-dire-need), so tracked as xfail.",
  strict=True,
)
def test_banana_body_bare_open_delimiter_not_miscounted(ir):
  # `(|` inside a body string (space-preceded => not a valid opener) should be verbatim content,
  # not counted as a nested banana open.  Self-contained: a trivial `dsl` kind, no graal dependency.
  r = ir(
    'lang x(|\n  echo "has (| here"\n|)\n',
    decl="from cmk import dsl\ndsl lang(entrypoint=cat)(| |)\n",
    ok=False,
  )
  assert r.ok, r.stderr
  assert "unbalanced banana" not in r.stderr
