"""End-to-end CMK-language tests via the reusable demo-runner.

These exercise the `run_demo` fixture (conftest.py), which runs a real
`demos/cmk/*.cmk` file through the actual `mk.interpret!` entrypoint
(CMK_SUPERVISOR=1, cwd=repo) -- the same path as `make demos/cmk`, but
label/project-scoped so docker cleanup never touches the dev's state.

The fixture generalizes to ANY demo; we don't run them all. The `bind*` demos
are the primary demonstration (file/target/script binding into containers);
structured-io and container-dispatch add the JSON-IO and `namespace` dispatch
idioms. All build/pull images, so they're [integration, needs_docker] and slow.
"""

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]


def test_demo_bind_file(run_demo):
  # polyglot.bind.file: bind demos/data/test-file.py to a python container.
  r = run_demo("demos/cmk/bind-file.cmk", timeout=900)
  assert r.ok, r.stderr
  assert "hello world foo=notset" in r.stdout


def test_demo_bind_target(run_demo):
  # compose.bind.target decorator: a target runs inside the debian container.
  r = run_demo("demos/cmk/bind-target.cmk")
  assert r.ok, r.stderr
  assert "hello container debian" in r.stdout


def test_demo_bind_script(run_demo):
  # ⨖ script-blocks + compose.bind.script: scripts run in their containers.
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


def test_demo_space_indented(run_demo):
  # Python-style SPACE-indented recipe bodies compile (spaces -> tab) and run.
  r = run_demo("demos/cmk/space-indented.cmk")
  assert r.ok, r.stderr
  assert "space line one" in r.stdout
  assert "space line two" in r.stdout


def test_demo_io_pushd(run_demo):
  # `ᝏio.pushd(dir)` decorator: EVERY command in the target runs from `dir`
  # (pwd is the subdir; the relative `marker.txt` resolves there), and because it
  # uses bash `pushd`, the body can `popd` back to the caller's dir.
  r = run_demo("demos/cmk/io.pushd.cmk")
  assert r.ok, r.stderr
  assert (
    "cwd=.tmp.pushd.demo" in r.stdout
  )  # all commands ran in the pushed dir
  assert "in-the-subdir" in r.stdout  # relative file resolved there
  assert "after popd, cwd=" in r.stdout  # body popped back out


# More lightweight demos (no heavy interpreters: rag/ollama/lean/just excluded).
# These are jb/jq-light or host-only, exercising additional idioms.


def test_demo_user_dialect(run_demo):
  # User-defined dialect: `cmk_dialect :::` remaps glyphs (⏪️/⏩️ -> jb/jq).
  r = run_demo("demos/cmk/user-dialect.cmk")
  assert r.ok, r.stderr
  assert "val" in r.stdout


def test_demo_kwarg_parsing(run_demo):
  # `ᝏargs.from_json(...)` decorator: JSON kwargs with per-key defaults.
  r = run_demo("demos/cmk/kwarg-parsing.cmk")
  assert r.ok, r.stderr
  assert "shape=triangle color=red name=default" in r.stdout


def test_demo_kwarg_parsing_2(run_demo):
  # args.from_json + args.from_env (env override) chained via flux.pipeline.
  r = run_demo("demos/cmk/kwarg-parsing-2.cmk")
  assert r.ok, r.stderr
  assert "shape=square color=green name=Bob" in r.stdout


def test_demo_script_dispatch_host(run_demo):
  # compose.import.script: a define-block runs as a HOST target (no container).
  r = run_demo("demos/cmk/script-dispatch-host.cmk")
  assert r.ok, r.stderr
  assert "multiline stuff" in r.stdout
  assert "Iteration 2" in r.stdout


def test_demo_underload(run_demo):
  # mk.import.def: the CMK port imports its lexer (`ul.lexer`) from the
  # demos/underload.mk twin, then runs the esolang host-side (jq/awk/io.stack).
  r = run_demo("demos/cmk/underload.cmk")
  assert r.ok, r.stderr
  assert "Hello, world!" in r.stdout  # push + print
  assert "BA" in r.stdout  # swap + cat
  assert "(a(:^)*S):^" in r.stdout  # quine: byte-exact self-output


# --- sugar-block family: functional runs (alpine / sh interpreter) -----------
# The CMK sugar blocks transpile to import macros that normally need heavy
# interpreters (elixir/lean/python) to *run*. Here we exercise them end-to-end
# with a trivial alpine image + sh, proving each block actually runs -- not
# just that it transpiles (fast compile-containment checks live in
# test_compiler_cmk.py). Compiled then run via __main__ (no supervisor).


def _run_cmk(cmk, project, src):
  """Compile CMK `src` and run its `__main__` via plain make."""
  c = cmk("mk.compile", stdin=src)
  assert c.ok, c.stderr
  project.seed_compose_mk()
  project.write("out.mk", "include compose.mk\n" + c.stdout)
  return project.run("__main__", makefile="out.mk", timeout=300)


def test_sugar_polyglot_block(cmk, project):
  # `⟦…⟧ with <img>, <interp> as container`: the code-block runs in the
  # interpreter container. alpine + sh runs a shell snippet.
  r = _run_cmk(
    cmk,
    project,
    "⟦ hw\necho POLYGLOT-OK\n⟧ with alpine:3.21.2, sh as container\n"
    "__main__: hw\n",
  )
  assert r.ok, r.stderr
  assert "POLYGLOT-OK" in r.stdout


def test_sugar_script_block(cmk, project):
  # `⨖…⨖ with img=<img> … as docker_context` binds a script to an image.
  # docker.bind.script defaults entrypoint=bash, so pass entrypoint=sh for
  # alpine (no bash).
  r = _run_cmk(
    cmk,
    project,
    "⨖ myscript\necho SCRIPT-OK\n"
    "⨖ with img=alpine:3.21.2 entrypoint=sh as docker_context\n"
    "__main__: myscript\n",
  )
  assert r.ok, r.stderr
  assert "SCRIPT-OK" in r.stdout


def test_sugar_dockerfile_block(cmk, project):
  # `⫻ Dockerfile.<n> … ⫻` -> docker.import.def: build the image, then run a
  # command in it (entrypoint=none runs the bare command directly).
  r = _run_cmk(
    cmk,
    project,
    "⫻ Dockerfile.mytool\nFROM alpine:3.21.2\n⫻\n"
    "__main__: mytool.build\n\tentrypoint=none cmd=whoami this.mytool\n",
  )
  assert r.ok, r.stderr
  assert "root" in r.stdout


def test_sugar_compose_string_block(cmk, project):
  # `⋘…⋙` -> compose.import.string: the inline compose YAML becomes a
  # root-level target family; `<stem>.services` lists its services.
  r = _run_cmk(
    cmk,
    project,
    "⋘ mycompose\nservices:\n  appsvc:\n    image: alpine:3.21.2\n⋙\n"
    "__main__:\n\tthis.mycompose.services\n",
  )
  assert r.ok, r.stderr
  assert "appsvc" in r.stdout
