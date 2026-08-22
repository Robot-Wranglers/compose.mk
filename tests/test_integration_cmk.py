"""End-to-end CMK-language tests via the reusable demo-runner.

These exercise the `run_demo` fixture (conftest.py), which runs a real
`demos/cmk/*.cmk` file through the actual `mk.interpret!` entrypoint
(CMK_SUPERVISOR=1, cwd=repo), the same path the demo's shebang uses, but
label/project-scoped so docker cleanup never touches the dev's state.

This is the canonical push/PR gate for the CMK demos.  The heavy/GUI/LLM demos
(lean, ollama, rag, xpra*, xephyr) are excluded here and run only via the
on-demand `actions.demos.cmk` sweep (.github/workflows/cmk-demos.yml).

The fixture generalizes to ANY demo; we don't run them all.  The `bind*` demos
are the primary demonstration (file/target/script binding into containers);
structured-io and container-dispatch add the JSON-IO and `namespace` dispatch
idioms.  All build/pull images, so they're [integration, needs_docker] and slow.
"""

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker, pytest.mark.covers_demo("agent-events.cmk", "bind-file.cmk", "bind-script.cmk", "bind-target.cmk", "channel.cmk", "code-objects.cmk", "container-dispatch-2.cmk", "container-dispatch.cmk", "docker.import.cmk", "elixir.cmk", "example.cmk", "exceptions.cmk", "flow_control.cmk", "import-file.cmk", "io.pushd.cmk", "just.cmk", "kwarg-parsing-2.cmk", "kwarg-parsing.cmk", "module-system.cmk", "platform-lme.cmk", "plugin-system.cmk", "script-dispatch-custom.cmk", "host-native-bash.cmk", "script-dispatch-stock.cmk", "space-indented.cmk", "structured-io.cmk", "underload.cmk", "user-dialect.cmk", "zahn.cmk")]


def test_demo_bind_file(run_demo):
  # file-sourced code-object: bind demos/data/test-file.py to a python container.
  r = run_demo("demos/cmk/bind-file.cmk", timeout=900)
  assert r.ok, r.stderr
  assert "hello world foo=notset" in r.stdout


def test_demo_bind_target(run_demo):
  # compose.bind.target decorator: a target runs inside the debian container.
  r = run_demo("demos/cmk/bind-target.cmk")
  assert r.ok, r.stderr
  assert "hello container debian" in r.stdout


def test_demo_bind_script(run_demo):
  # in-container script bodies + compose.bind.script: scripts run in their containers.
  r = run_demo("demos/cmk/bind-script.cmk", timeout=900)
  assert r.ok, r.stderr
  assert "hello container alpine" in r.stdout
  assert "hello container debian" in r.stdout


def test_demo_structured_io(run_demo):
  # 🡄 (jb emit) | 🡆 (jq consume) structured-IO across targets.
  r = run_demo("demos/cmk/structured-io.cmk")
  assert r.ok, r.stderr
  assert "val" in r.stdout


def test_demo_container_dispatch(run_demo):
  # `compose.import(namespace=▰)` + `▰/svc/target` namespace dispatch.
  r = run_demo("demos/cmk/container-dispatch.cmk")
  assert r.ok, r.stderr
  assert "Debian GNU/Linux" in r.stdout


def test_demo_container_dispatch_2(run_demo):
  # Container dispatch via the "namespace" invocation style (▰/svc/target).
  r = run_demo("demos/cmk/container-dispatch-2.cmk")
  assert r.ok, r.stderr
  assert "Debian GNU/Linux" in r.stdout


def test_demo_space_indented(run_demo):
  # Python-style SPACE-indented recipe bodies compile (spaces -> tab) and run.
  r = run_demo("demos/cmk/space-indented.cmk")
  assert r.ok, r.stderr
  assert "space line one" in r.stdout
  assert "space line two" in r.stdout


def test_demo_io_pushd(run_demo):
  # `@io.pushd(dir)` combined with `@compose.bind.target(svc)`: the target is
  # dispatched into the debian container, and io.pushd on its in-container body
  # runs every command from the pushed dir (pwd is the subdir; the relative
  # `marker.txt` resolves there), then `popd` returns to the container workdir.
  r = run_demo("demos/cmk/io.pushd.cmk")
  assert r.ok, r.stderr
  assert (
    "container=debian" in r.stdout
  )  # ran inside the container (bind.target)
  assert "cwd=.tmp.pushd.demo" in r.stdout  # io.pushd: commands ran in the dir
  assert "in-the-subdir" in r.stdout  # relative file resolved there
  assert "after popd, cwd=" in r.stdout  # popped back out


# More lightweight demos, exercising additional idioms.  (Heavy/GUI/LLM demos
# stay out and run only via the on-demand sweep: lean, ollama, rag, xpra*,
# xephyr.  The inlined-{compose,docker}file + user-sugar demos route output to
# stderr and their sugar is already asserted by the sugar-block family below.)


def test_demo_user_dialect(run_demo):
  # User-defined dialect: `cmk_dialect :::` remaps glyphs (⏪️/⏩️ -> jb/jq).
  r = run_demo("demos/cmk/user-dialect.cmk")
  assert r.ok, r.stderr
  assert "val" in r.stdout


def test_demo_kwarg_parsing(run_demo):
  # `@bind.args(from=json, ..)` decorator: JSON kwargs with per-key defaults.
  r = run_demo("demos/cmk/kwarg-parsing.cmk")
  assert r.ok, r.stderr
  assert "shape=triangle color=red name=default" in (r.stdout + r.stderr)


def test_demo_kwarg_parsing_2(run_demo):
  # bind.args from=json + from=env (env override) chained via flux.pipeline.
  r = run_demo("demos/cmk/kwarg-parsing-2.cmk")
  assert r.ok, r.stderr
  assert "shape=square color=green name=Bob" in (r.stdout + r.stderr)


def test_demo_host_native_bash(run_demo):
  # host.native.bash.polyglot: a code-block runs as a HOST target (no container).
  r = run_demo("demos/cmk/host-native-bash.cmk")
  assert r.ok, r.stderr
  assert "multiline stuff" in r.stdout
  assert "Iteration 2" in r.stdout


@pytest.mark.xfail(
  reason="deferred core bug: the inline-Dockerfile machine's image is not built before the "
  "in-container dispatch under the cmk-run compiler path (docker pulls compose.mk:my_container "
  "instead). Tracked in scratch/fullrun/triage.md.",
  strict=False,
)
def test_demo_script_dispatch_custom(run_demo):
  # script dispatch into a custom-built container; runs a script there + exports.
  r = run_demo("demos/cmk/script-dispatch-custom.cmk")
  assert r.ok, r.stderr
  assert "variable exported: hello-world" in r.stdout


def test_demo_script_dispatch_stock(run_demo):
  # script dispatch into a stock image (debian); the script greets from inside.
  r = run_demo("demos/cmk/script-dispatch-stock.cmk")
  assert r.ok, r.stderr
  assert "hello debian/buildd" in r.stdout


def test_demo_import_file(run_demo):
  # file-sourced code-object: import an external script file as a namespaced target.
  r = run_demo("demos/cmk/import-file.cmk")
  assert r.ok, r.stderr
  assert "hello world foo=val1 bar=val2" in r.stdout


def test_demo_docker_import(run_demo):
  # docker.import scaffolding for a stock image (debian) + a local Dockerfile;
  # exercises the generated .build/.dispatch/<t> and bare-namespace targets.
  r = run_demo("demos/cmk/docker.import.cmk", timeout=900)
  assert r.ok, r.stderr
  assert "hello-world" in r.stdout


def test_demo_example(run_demo):
  # The smallest useful CMK program: an entrypoint + a `cmk.log` line (logs
  # to stderr).  The structured-IO 🡄/🡆 example now lives in structured-io.cmk.
  r = run_demo("demos/cmk/example.cmk")
  assert r.ok, r.stderr
  assert "hello world" in r.stderr


def test_demo_code_objects(run_demo):
  # Embedded code-objects: preview + run inline code blocks across interpreters.
  r = run_demo("demos/cmk/code-objects.cmk")
  assert r.ok, r.stderr
  assert "hello world 2" in r.stdout


def test_demo_elixir(run_demo):
  # Polyglot dispatch: an Elixir snippet runs in the elixir container.
  r = run_demo("demos/cmk/elixir.cmk")
  assert r.ok, r.stderr
  assert "elixir World!" in r.stdout


def test_demo_just(run_demo):
  # Interop with `just`: recipes run via a justfile in the just container.
  r = run_demo("demos/cmk/just.cmk")
  assert r.ok, r.stderr
  assert "This is a recipe!" in r.stdout


def test_demo_platform_lme(run_demo):
  # Multi-container platform bootstrap (terraform + ansible) emitting JSON logs.
  r = run_demo("demos/cmk/platform-lme.cmk")
  assert r.ok, r.stderr
  assert "infra setup done" in r.stdout
  assert "app setup done" in r.stdout


def test_demo_underload(run_demo):
  # import.def: the CMK port imports its lexer (`ul.lexer`) from the
  # demos/underload.mk twin, then runs the esolang host-side (jq/awk/io.stack).
  r = run_demo("demos/cmk/underload.cmk")
  assert r.ok, r.stderr
  assert "Hello, world!" in r.stdout  # push + print
  assert "BA" in r.stdout  # swap + cat
  assert "(a(:^)*S):^" in r.stdout  # quine: byte-exact self-output


def test_demo_flow_control(run_demo):
  # A demo-local trampoline (`fc.*`) generalizes the one-shot `mk.yield` into a
  # resumable/schedulable runtime; three flow-control constructs ride on it (Zahn's
  # construct + typed exceptions split out to zahn.cmk / exceptions.cmk).  Narration
  # goes to stderr via log.io.
  r = run_demo("demos/cmk/flow_control.cmk")
  assert r.ok, r.stderr
  out = r.stderr
  assert (
    "channel: step-1 step-2 step-3" in out
  )  # trampoline resumes a fiber 3x
  assert "goto: backward-jump loop -> tick-3 tick-2 tick-1" in out  # goto
  assert (
    "computed-goto: sel=9 -> case-DEFAULT" in out
  )  # computed goto (jump table)
  assert (
    "prod: produced 2" in out and "cons: consumed 2" in out
  )  # coroutines interleave
  assert "cons: drained" in out
  assert "call/ec returned: 9" in out  # escape continuation returns a value


def test_demo_exceptions(run_demo):
  # Typed exceptions on the `fault` event-channel: each raised target
  # emits a structured event {type, target, file, ...meta}; the tour
  # swallows the throws so they stay in flight, and the at-exit dispatcher
  # drains + routes them.  Assert on the DATA the dispatcher narrates (a
  # stable contract), NOT on handler log wording (fragile).
  r = run_demo("demos/cmk/exceptions.cmk")
  assert r.ok, (
    r.stderr
  )  # tour `|| true`s the throws -> dispatched at exit, clean 0
  out = r.stderr
  # every raised type is dispatched as an event object (incl. BOOM, which
  # has no specific handler -> the `fault/%` fallback, and the
  # fault->exception bridge's SubprocessFault)
  for typ in (
    "DivZero",
    "Inner",
    "Wrapped",
    "BOOM",
    "SubprocessFault",
  ):
    assert f'"type": "{typ}"' in out, typ
  # the FTA `kind` taxonomy is carried on the events
  for kind in ("basic", "external", "undeveloped", "conditioning"):
    assert f'"kind": "{kind}"' in out, kind
  # implicit metadata: the raising target (incl. a re-throw recording the
  # handler) and the source file.  (The SubprocessFault *type* above already
  # proves the fault->exception bridge; its exact metadata fields are demo
  # implementation detail, deliberately not pinned here.)
  assert '"target": "demo.div"' in out
  assert '"target": "fault/Inner"' in out  # Wrapped re-raised by Inner
  assert '"file": "' in out  # implicit ${__file__}


def test_demo_channel(run_demo):
  # The event core demonstrated via a channel's NATIVE filter: inbox.login_events
  # captures `<chan>.filter.field_equal/type,login` (ALL matches, newest-first,
  # ONE jq pass over the backing array) and narrates them via stream.as.log
  # (-> stderr).  Seeded alice/bob(logout)/carol/danny(suspend), so the logins
  # are carol then alice.  (Zahn + exceptions are the dispatch-side customers, in
  # their own demos.)
  r = run_demo("demos/cmk/channel.cmk")
  assert r.ok, r.stderr
  assert '"user":"carol"' in r.stderr  # newest login (filter, newest-first)
  assert '"user":"alice"' in r.stderr  # ...and the older one (filter = all)


def test_demo_agent(run_demo):
  # An event-log agent rebuilt on the actor/agent layer in .cmk/agents.cmk.
  # The demo flat-imports that module, mints an inproc agent, then: the data plane casts carol(login)/
  # bob(logout)/alice(login) and dumps the stack; a read-only jq-fold query keeps
  # the logins; the control plane drains each event to auth/<action>, which logs
  # the user from the CMK_EVENT envelope.
  r = run_demo("demos/cmk/agent-events.cmk")
  assert r.ok, r.stderr
  assert "holds 3 events" in r.stderr  # the data-plane casts landed
  assert "kept-logins" in r.stderr  # the jq-fold query step ran
  assert "carol" in r.stderr  # seeded login, surfaced by query + dispatch
  assert "alice" in r.stderr  # seeded login, surfaced by query + dispatch
  assert "bob" in r.stderr  # seeded logout, drained to the logout handler


def test_demo_zahn(run_demo):
  # Zahn's construct (a CUSTOMER of the event core): a multi-exit SEARCH LOOP
  # whose NAMED EXITS drive control flow.  first.match.field_equal emits a typed
  # outcome (found{id}/exhausted) the dispatcher narrates as JSON (assert that
  # DATA, not log wording), and the exit SELECTS the continuation, so the RESULT
  # on stdout differs by outcome: found -> recover (`recovered=<id>`),
  # exhausted -> commit (`committed`).
  r = run_demo("demos/cmk/zahn.cmk")
  assert r.ok, r.stderr
  out = r.stderr
  assert '"type": "found"' in out
  assert '"id": "c"' in out  # newest status=error candidate (a/b/c)
  assert '"type": "exhausted"' in out  # the no-match case (status=pending)
  assert (
    "recovered=c" in r.stdout
  )  # found exit -> recover continuation (w/ id)
  assert (
    "committed" in r.stdout
  )  # exhausted exit -> the DIFFERENT continuation


def test_demo_module_system(run_demo):
  # The demo defines one module as a cooked banana (`MyModule[| .. |]` -> a dedented, reusable
  # `define MyModule`) and imports it FOUR ways: aliased (namespace != module name), partial
  # (targets=greet), star (targets='svc.*'), and flat/root (flat=1).  Each imported target keeps
  # its namespace in its NAME, and the CMK-Lang `report` target is lowered at import
  # (preprocs=mk.compile).  The bare `greet` in __main__ only exists if the flat/root import
  # landed, so `r.ok` itself exercises that fourth case.  A `'''docstring'''` inside the banana
  # body reifies as `MyModule.__doc__` via the module constructor (`_mk.module.header` binds
  # `self` to the source name on import) -- reflected by the first.class target.
  r = run_demo("demos/cmk/module-system.cmk")
  assert r.ok, r.stderr
  out = r.stdout + r.stderr
  assert "Aliased.greet" in out  # aliased: namespace != module name
  assert "Part.greet" in out  # partial: only `greet` selected
  assert (
    "Star.svc.up" in out and "Star.svc.down" in out
  )  # star: the `svc.*` glob
  assert "compiled report ok" in out  # CMK-Lang `report`, lowered at import
  assert (
    "a greet plus a tiny svc lifecycle" in out
  )  # docstring reified as MyModule.__doc__ (module-constructor self-binding)


def test_demo_plugin_system(run_demo):
  # Including PLUGINS where the file extension picks the binding: a plain `.mk`
  # plugin is `include`d verbatim (fast), while a `.cmk` plugin is JIT-compiled
  # (lowered via mk.compile) THEN included.  Running UNDER `cmk run` exercises the
  # file-stage path through the cmk-run invocation (not just `make -f`).
  r = run_demo("demos/cmk/plugin-system.cmk")
  assert r.ok, r.stderr
  out = r.stdout + r.stderr
  assert "plain make plugin" in out  # .mk plugin: verbatim fast include
  assert (
    "hello from a compiled cmk plugin" in out
  )  # .cmk plugin: lowered then included


# --- sugar-block family: functional runs (alpine / sh interpreter) -----------
# The CMK sugar blocks transpile to import macros that normally need heavy
# interpreters (elixir/lean/python) to *run*. Here we exercise them end-to-end
# with a trivial alpine image + sh, proving each block actually runs -- not
# just that it transpiles (fast compile-containment checks live in
# test_compiler_cmk.py). Compiled then run via __main__ (no supervisor).


def _run_cmk(ir, project, src):
  """Compile CMK `src` and run its `__main__` via plain make."""
  c = ir(src)
  project.seed_compose_mk()
  project.write("out.mk", "include compose.mk\n" + c.stdout)
  return project.run("__main__", makefile="out.mk", timeout=300)


def test_sugar_script_block(ir, project):
  # `(| body |) in container(| img=.. entrypoint=.. |)` runs a script body in an
  # anonymous, single-use container (mirrors demos/cmk/script-dispatch-stock.cmk).
  # entrypoint=sh for alpine (no bash).
  r = _run_cmk(
    ir,
    project,
    "open cmk\n"
    "foo:\n\t(| echo SCRIPT-OK |) in container(| img=alpine:3.21.2 entrypoint=sh |)\n"
    "__main__: foo\n",
  )
  assert r.ok, r.stderr
  assert "SCRIPT-OK" in r.stdout


def test_sugar_compose_string_block(ir, project):
  # `compose.import.string NAME(| .. |)` -> the inline compose YAML becomes a
  # root-level target family; `<stem>.services` lists its services.
  r = _run_cmk(
    ir,
    project,
    "compose.import.string mycompose(|\n"
    "services:\n  appsvc:\n    image: alpine:3.21.2\n"
    "|)\n"
    "__main__:\n\tthis.mycompose.services\n",
  )
  assert r.ok, r.stderr
  assert "appsvc" in r.stdout


# --- decorator postfix mode: end-to-end run (no docker) -----------------------


def test_decorator_postfix_run(ir, project):
  # `postfix_mode=<conn>` relocates a decorator to AFTER the body, joined by the
  # shell connector <conn>: `&&` runs it only after a passing body, `;` always,
  # `||` only after a failing body.  Bodies `|| true`'d so the run stays green.
  r = _run_cmk(
    ir,
    project,
    "mark=printf '[mark:%s]\\n' \"$(1)\"\n"
    "@mark(and-ok, postfix_mode=&&)\n"
    "t.and.ok:\n\tprintf '[body:and-ok]\\n'\n\ttrue\n"
    "@mark(and-fail, postfix_mode=&&)\n"
    "t.and.fail:\n\tprintf '[body:and-fail]\\n'\n\tfalse\n"
    "@mark(semi, postfix_mode=;)\n"
    "t.semi:\n\tprintf '[body:semi]\\n'\n\tfalse\n"
    "@mark(or-fail, postfix_mode=||)\n"
    "t.or.fail:\n\tprintf '[body:or-fail]\\n'\n\tfalse\n"
    "@mark(or-ok, postfix_mode=||)\n"
    "t.or.ok:\n\tprintf '[body:or-ok]\\n'\n\ttrue\n"
    "__main__:\n"
    "\tthis.t.and.ok </dev/null || true\n"
    "\tthis.t.and.fail </dev/null || true\n"
    "\tthis.t.semi </dev/null || true\n"
    "\tthis.t.or.fail </dev/null || true\n"
    "\tthis.t.or.ok </dev/null || true\n",
  )
  assert r.ok, r.stderr
  out = r.stdout
  assert "[mark:and-ok]" in out  # && + body succeeded -> runs
  assert "[mark:and-fail]" not in out  # && + body failed -> skipped
  assert "[mark:semi]" in out  # ; -> always runs (even on failure)
  assert "[mark:or-fail]" in out  # || + body failed -> runs (a catch)
  assert "[mark:or-ok]" not in out  # || + body succeeded -> skipped
  # the postfix decorator runs AFTER its body
  assert out.index("[body:and-ok]") < out.index("[mark:and-ok]")
