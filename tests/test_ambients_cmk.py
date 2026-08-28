"""Ambient-calculus module ops: `*` (flat dissolve) and `open/import` kwargs.

A module is an ambient (a named, bounded place holding definitions).  `* X` /
`open X flat=1` DISSOLVE its boundary -- merge its members verbatim into the
current namespace (Cardelli-Gordon `open n`); `import X as N` MOUNTS it nested
(namespace=N).  See demos/cmk/ambients.cmk + TODO-banana-algebra.md.
"""

from pathlib import Path

import pytest

pytestmark = [pytest.mark.compiler, pytest.mark.covers_demo("ambients.cmk", "ambients-open.cmk", "banana-in.cmk", "banana-svc.cmk")]

REPO = Path(__file__).resolve().parent.parent


def test_star_module_open_removed(ir):
  # `* <name>` module-open no longer exists -- naked `*` is the inline-ambient prefix
  # (`*(| .. |)`).  A `* <name>` line lowers to a loud error pointing at `open`.
  out = ir("* flux\n")
  assert "$(error" in out and "removed" in out


def test_open_path_flat_dissolves(ir):
  # a `/`-path arg to `open` dissolves the file through the `path` ambient subkind:
  # its ref is staged into a throwaway def and routed via `ambient.dissolve kind=path`.
  out = ir("open demos/data/ambients.probe.cmk\n")
  assert "demos/data/ambients.probe.cmk" in out and "kind=path" in out and "flat=1" in out
  assert "cmk.open,demos/cmk" not in out  # a `/`-path is NOT a namespace -> no register


# --- `*(| .. |)` inline ambient dissolve (the inline dual of `* <module>`) ------
# A star on an anonymous banana splices its body flat into the current namespace, via
# the same import.module path.  Reuses the shared banana opener (a synthetic name + the
# `ambient.dissolve` ctor); not a separate normalizer.


def test_star_banana_lowers_to_dissolve(ir):
  out = ir("*(|\nx=1\n|)\n")
  assert "define __ambient_" in out              # synthetic-named define holds the body
  assert "$(call ambient.dissolve, def=__ambient_" in out  # after-close splice hook


def test_star_banana_oneliner(ir):
  out = ir("*(| z:; @echo hi |)\n")
  assert "$(call ambient.dissolve, def=__ambient_" in out


def test_star_banana_space_before_open(ir):
  # `* (|` (space) lowers the same as `*(|` -- the star prefix, not the module form.
  out = ir("* (|\nx=1\n|)\n")
  assert "$(call ambient.dissolve, def=__ambient_" in out


def test_ctor_star_passes_kind(ir):
  # `ctor *(||)` -> the ctor becomes the dissolve KIND: one kind-dispatched call
  # `$(call ambient.dissolve, def=__t kind=ctor)` (not a separate ctor call).  bare
  # `*(||)` is the kind-empty (inline) case.
  out = ir("declare *(|\nx=1\n|)\n")
  assert "define __ambient_" in out
  assert "$(call ambient.dissolve, def=__ambient_" in out and "kind=declare)" in out
  bare = ir("*(| x=1 |)\n")
  assert "$(call ambient.dissolve, def=__ambient_" in bare and "kind=" not in bare


def test_ctor_star_path(ir):
  # a leading ctor path (multi-word) joins with dots into the kind.
  out = ir("compose import *(| x=1 |)\n")
  assert "$(call ambient.dissolve, def=__ambient_" in out and "kind=compose.import)" in out


@pytest.mark.integration
def test_star_banana_dissolve_runs(cmk):
  # end-to-end: the dissolved body's var (make-var) + target splice in flat, so
  # `__main__: z` reaches the spliced target and sees the spliced variable.
  src = '*(|\nx=hello world\nz:; @echo "x=[${x}]"\n|)\n\n__main__: z\n'
  p = REPO / ".tmp.dissolve.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.dissolve.cmk", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    assert "x=[hello world]" in (r.stdout + r.stderr), (r.stdout + r.stderr)[-1500:]
  finally:
    p.unlink(missing_ok=True)


def test_open_threads_kwargs(ir):
  # a `kw=v` open threads its kwargs through the unified dissolve seam: the source is
  # staged into a throwaway def and routed via `ambient.dissolve kind=path`, which
  # forwards flat=/prefix=/.. down to import.module (path.__open__).
  out = ir("open flux, flat=1 prefix=v\n")
  assert "$(call ambient.dissolve, def=__opena_" in out and "kind=path" in out
  assert "flat=1" in out and "prefix=v" in out
  assert "cmk.open" not in out  # `open` emits no runtime call (the no-op was removed)


def test_import_threads_kwargs(ir):
  # `import` still emits the `cmk.import` resolution guard, then threads the load
  # through the same `ambient.dissolve kind=path` seam (kwargs forwarded to import.module).
  out = ir("import foo, strict=1\n")
  assert "$(call cmk.import,foo)" in out
  assert "$(call ambient.dissolve, def=__opena_" in out and "kind=path" in out
  assert "strict=1" in out


def test_bare_open_dissolves_via_module_subkind(ir):
  # a bare `open <name>` lowers to the lang.module.from dispatcher (star form); core-vs-disk resolves at import time.
  out = ir("open flux\n")
  assert "$(call lang.module.from,flux, *)" in out


# --- recipe `in <X>` mobility (dispatch into a named ambient) -----------------
# `(| body |) in X` lifts the body to a module define and hands it to ambient X's own
# dispatch; a `{k=v}` env rides along as a shell prefix.  A bare image is not an ambient.


def test_in_sugar_lowers_to_machine_callform(ir):
  # `(| body |) in NAME` (a plain interpreter) lowers to the machine callform: the lifted
  # block routes to NAME's `machine` target -- native host runners are named in full
  # (`in host.native.sh`) and dispatch by that name via `_cmk.host.machine`; no env channel.
  out = ir("foo:\n\t(| echo hi |) in host.native.sh\n")
  assert "${make} $(call _cmk.host.machine,host.native.sh)/" in out
  assert "define __lambda" in out


def test_ambient_env_channel_reserved(ir):
  # the dynamic `{ambient=X}` channel on a BARE banana is reserved (an anonymous banana has no
  # callforms) -- use the `in X` operator instead.
  out = ir("foo:\n\t(| echo hi |){ambient=python}\n")
  assert "$(error" in out and "NotImplemented/Grammar/anon-callform" in out


def test_in_composes_with_args_and_env(ir):
  # a plain interpreter -> machine callform, args ride the CMK_LAMBDA_ARGV prefix.
  out = ir("foo:\n\t(| src |) in host.native.python (a,b)\n")
  assert "${make} $(call _cmk.host.machine,host.native.python)/" in out and "a b" in out
  # a container: an inline anonymous `container(| img=.. |)` mints an ambient (a bare image is no
  # longer a magic string), and the `{..}` env channel rides alongside it.
  combined = ir("open cmk\nfoo:\n\t(| src |) in container(| img=alpine:3.21 |) {E=1}\n")
  assert "define __ambient_" in combined and "$(call container, def=__ambient_" in combined
  assert "E=1 ${make}" in combined and "$(call _cmk.host.machine,__ambient_" in combined


def test_plain_lambda_callform_reserved(ir):
  # a bare `(| .. |)(args)` (no `in`, no ctor) is reserved -- an anonymous banana has no callforms.
  out = ir("foo:\n\t(| echo hi |)(x)\n")
  assert "$(error" in out and "NotImplemented/Grammar/anon-callform" in out


def test_out_lowers_to_machine_callform(ir):
  # `out` = the enclosing/host ambient (§11): lowers to a `$(call _cmk.host.machine,out)/` callform
  # (which resolves `out` -> the `outwards/%:` navigation target), not the legacy env channel.
  out = ir("foo:\n\t(| echo hi |) out\n")
  assert "${make} $(call _cmk.host.machine,out)/" in out


def test_out_composes_with_args(ir):
  out = ir("foo:\n\t(| echo hi |) out (x)\n")
  assert "${make} $(call _cmk.host.machine,out)/" in out and "CMK_LAMBDA_ARGV='x'" in out


@pytest.mark.integration
def test_lambda_args_reach_body(cmk):
  # regression for the argv-forwarding fix: `(| .. |)(a,b)` must pass a,b to the
  # lambda body's positional args at runtime (docker-free `in host.native.sh`), not leak them
  # as make goals ("No rule to make target 'alpha'").  Runtime, not compile-shape.
  src = "foo:\n\t(| printf 'ARGV:[%s][%s]\\n' \"$1\" \"$2\" |) in host.native.sh (alpha,beta)\n"
  p = REPO / ".tmp.argv.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.argv.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "ARGV:[alpha][beta]" in out, out[-1500:]
    # the regression is specifically the lambda ARGS leaking as goals; assert on the
    # arg names, not a bare "No rule.." (the outer `cmk run` dispatch emits its own
    # unrelated "No rule to make target 'run'" supervisor noise on every program).
    assert "No rule to make target 'alpha'" not in out, out[-1500:]
    assert "No rule to make target 'beta'" not in out, out[-1500:]
  finally:
    p.unlink(missing_ok=True)


def test_capture_in_is_deferred_error(ir):
  # capture-mobility (`x <- (| .. |) in X`) is not supported yet -> loud error.
  out = ir("foo:\n\ty <- (| src |) in host.native.python\n")
  assert "$(error" in out and "capture-mobility" in out


# --- polyglot host-interpreter import DERIVED over `in` (§10 inversion) --------


@pytest.mark.integration
def test_polyglot_import_entrypoint_host(cmk):
  # `code def=X entrypoint=python` mints a HOST polyglot (img=HOST_AMBIENT) AND wraps it in
  # the code-object scaffold (code.unbound), so the host route gets the SAME surface as the
  # container route: `calc` runs the block on the host (via the polyglot's `.__call__` host branch
  # -> cmk.host.exec, entrypoint prepended to cmd), and the scaffold (`.to.file`, `.preview`, ..) exists.
  src = (
    "define calc\nprint(6*7)\nendef\n"
    "$(eval $(call code, def=calc entrypoint=python))\n"
    "foo: calc\n"
  )
  p = REPO / ".tmp.polyin.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.polyin.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "42" in out, out[-1500:]  # the block ran on the host
    # the scaffold now exists for the host route too (docker-free probe: `.to.file` dumps the block)
    r2 = cmk("cmk", "run", ".tmp.polyin.cmk", "calc.to.file", cwd=REPO, timeout=120,
             env={"CMK_SUPERVISOR": "1"})
    assert r2.returncode == 0, (r2.stdout + r2.stderr)[-1500:]
  finally:
    p.unlink(missing_ok=True)


@pytest.mark.integration
def test_polyglot_import_entrypoint_at_target(cmk):
  # `entrypoint=@T` is the target category of the ONE command concept: a `@`-prefixed entrypoint
  # dispatches the materialized block to make-target T (`${make} T/<file>`), so a target-interpreter
  # flows through the SAME polyglot route as a host/container command -- no separate `bind=` path needed.
  src = (
    "my_runner/%:; @printf 'RAN[%s]\\n' \"$$(cat $*)\"\n"
    "define blk\nblock-body\nendef\n"
    "$(eval $(call code, def=blk entrypoint=@my_runner))\n"
    "foo: blk\n"
  )
  p = REPO / ".tmp.atrunner.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.atrunner.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "RAN[block-body]" in out, out[-1500:]  # the block was handed to my_runner
  finally:
    p.unlink(missing_ok=True)


# --- banana-in.cmk demo: recipe bananas run directly over `in` -------------


def test_polyglot_in_demo_compiles(cmk):
  # the demo is pure recipe banana `(| body |) in X` -- host interpreter
  # (`in host.native.python`, `in host.native.sh`) and a container (`in <image> {entrypoint=..}`).
  r = cmk("cmk", "compile", "demos/cmk/banana-in.cmk", cwd=REPO, timeout=120,
          env={"CMK_SUPERVISOR": "1"})
  assert r.ok, r.stderr[-1500:]


@pytest.mark.integration
def test_polyglot_in_demo_runs(cmk):
  # __main__ (docker-free): the `hello`/`compute` targets run python bananas via
  # `in host.native.python`.  Routing is pinned by test_machine_hierarchy_cmk, not scraped here.
  r = cmk("cmk", "run", "demos/cmk/banana-in.cmk", cwd=REPO, timeout=120,
          env={"CMK_SUPERVISOR": "1"})
  out = r.stdout + r.stderr
  assert "factorial(10) = 3628800" in out, out[-1500:]
  assert "hello from a python ambient" in out, out[-1500:]


# --- `__ambients__.declare` registry: named container ambients (§10 phase-2) ---


@pytest.mark.integration
def test_container_is_a_machine_subkind(cmk):
  # `cmk.container <name>(| img=.. |)` mints a class instance: container IS-A machine (inherits its
  # `${self}/%:` target via `using bases=cmk.machine`) and, in its inline body, overrides `.run` to the
  # docker dispatch (`_crun`) and reads img/entrypoint from the instance body.  The KIND is a prelude
  # keyword, minted qualified (`cmk.container`); the bare `container` is bound only via `open cmk`.
  # also exercises the reflection layer: `.__mro__` (linearized base names, self first)
  # and the `issubclass` predicate that reads it -- container IS-A machine, not vice versa.
  src = (
    "cmk.container box(| img=golang:1.24 entrypoint=go |)\n"
    "foo:\n"
    "\t@printf 'cls=[%s] bases=[%s] mro=[%s] sub=[%s] notsub=[%s] img=[%s] run=[%s]\\n' "
    "\"$(box.__class__)\" \"$(cmk.container.__bases__)\" \"$(cmk.container.__mro__)\" "
    "\"$(call issubclass,cmk.container,cmk.machine)\" "
    "\"$(call issubclass,cmk.machine,cmk.container)\" "
    "\"$(box.img)\" \"$(box.run)\"\n"
  )
  p = REPO / ".tmp.container.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.container.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "cls=[cmk.container]" in out, out[-1500:]
    # container IS-A machine, which derives the `Runnable` protocol (EXECUTE, .run), the `Ambient`
    # protocol (MEMBERSHIP, registration + `.__ambient_parent__` -- was the `cmk.ambient` class) + the
    # capabilities mixin (img/build reads); so the MRO now carries Ambient + Runnable.
    assert "bases=[cmk.machine]" in out, out[-1500:]
    assert "mro=[Ambient Directory Feedable Loggable Named Runnable cmk.container cmk.container.capabilities cmk.machine]" in out, out[-1500:]
    assert "sub=[1]" in out, out[-1500:]  # issubclass(container, machine)
    assert "notsub=[]" in out, out[-1500:]  # NOT issubclass(machine, container)
    assert "img=[golang:1.24]" in out, out[-1500:]
    assert "run=[_crun/box]" in out, out[-1500:]  # docker .run override
  finally:
    p.unlink(missing_ok=True)


def test_dockerfile_is_a_container_subkind(cmk):
  # `Dockerfile NAME(| FROM .. |)` is the FIRST-CLASS embedded-Dockerfile form: the banana BODY is
  # the Dockerfile itself.  It mints a `cmk.Dockerfile` instance -- IS-A container (so it inherits
  # the `_crun` .run and the `.build`/`(| .. |) in <name>` surface) -- with `.img` force-prefixed
  # `compose.mk:NAME` and `.src := NAME` pointing the build at the instance's own value (no separate
  # `define Dockerfile.NAME` needed).  Parse-only: proves the wiring, no image build.
  src = (
    "open cmk\n"
    "Dockerfile mytool(|\n  FROM alpine:3.21.2\n|)\n"
    "foo:\n"
    "\t@printf 'mro=[%s] con=[%s] df=[%s] img=[%s] src=[%s] run=[%s]\\n' "
    "\"$(cmk.Dockerfile.__mro__)\" "
    "\"$(call isinstance,mytool,cmk.container)\" "
    "\"$(call isinstance,mytool,cmk.Dockerfile)\" "
    "\"$(mytool.img)\" \"$(mytool.src)\" \"$(mytool.run)\"\n"
  )
  p = REPO / ".tmp.dockerfile.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.dockerfile.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "con=[1]" in out, out[-1500:]                 # IS-A container
    assert "df=[1]" in out, out[-1500:]                  # IS-A Dockerfile
    assert "cmk.container" in out and "cmk.Dockerfile" in out, out[-1500:]  # container in the MRO
    assert "img=[compose.mk:mytool]" in out, out[-1500:]  # .img force-prefixed
    assert "src=[mytool]" in out, out[-1500:]            # build source = own value
    assert "run=[_crun/mytool]" in out, out[-1500:]      # inherited docker .run
  finally:
    p.unlink(missing_ok=True)


def test_container_recipe_body_builds_like_dockerfile(cmk):
  # THE MERGE (new form): a plain `container NAME(kwargs)(| FROM .. |)` with a RECIPE body
  # self-configures as a build IDENTICALLY to the `Dockerfile` form -- img force-prefixed
  # `compose.mk:NAME`, src the instance's own value, `_crun` .run.  So `container` with a recipe
  # body == `Dockerfile` (the thin alias).  Parse-only: proves the wiring, no image build.
  src = (
    "open cmk\n"
    "container built(entrypoint=sh)(|\n  FROM alpine:3.21.2\n|)\n"
    "foo:\n"
    "\t@printf 'con=[%s] img=[%s] src=[%s] run=[%s]\\n' "
    "\"$(call isinstance,built,cmk.container)\" "
    "\"$(built.img)\" \"$(built.src)\" \"$(built.run)\"\n"
  )
  p = REPO / ".tmp.container_recipe.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.container_recipe.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "con=[1]" in out, out[-1500:]                  # IS-A container
    assert "img=[compose.mk:built]" in out, out[-1500:]   # recipe body -> force-prefixed image
    assert "src=[built]" in out, out[-1500:]              # build source = own value (like Dockerfile)
    assert "run=[_crun/built]" in out, out[-1500:]
  finally:
    p.unlink(missing_ok=True)


def test_container_paren_config_pulls_not_builds(cmk):
  # DISCRIMINATION: a `container NAME(img=..)(| |)` with an EMPTY body -- or a legacy body-kwargs
  # `(| img=.. |)` -- is NOT a build.  img is the named image to PULL, src stays empty (`.build` a
  # noop).  Only a body with a token WITHOUT `=` (a recipe: FROM/RUN) flips it to build-from-body.
  src = (
    "open cmk\n"
    "container pulled(img=alpine:3.21.2 entrypoint=sh)(| |)\n"
    "container legacy(| img=scratch |)\n"
    "foo:\n"
    "\t@printf 'p_img=[%s] p_src=[%s] l_img=[%s] l_src=[%s]\\n' "
    "\"$(pulled.img)\" \"$(pulled.src)\" \"$(legacy.img)\" \"$(legacy.src)\"\n"
  )
  p = REPO / ".tmp.container_pull.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.container_pull.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "p_img=[alpine:3.21.2]" in out and "p_src=[]" in out, out[-1500:]  # paren img -> pull
    assert "l_img=[scratch]" in out and "l_src=[]" in out, out[-1500:]        # legacy kwargs -> pull
  finally:
    p.unlink(missing_ok=True)


# --- `&` serviceize -> handle (banana-svc.cmk spike) --------------------------


def test_banana_svc_compiles(cmk):
  # the compose-service handle (docker) + the actor handle compile together.
  r = cmk("cmk", "compile", "demos/cmk/banana-svc.cmk", cwd=REPO, timeout=120,
          env={"CMK_SUPERVISOR": "1"})
  assert r.ok, r.stderr[-1500:]


@pytest.mark.integration
def test_banana_svc_actor_handle_runs(cmk):
  # __main__ = the inproc actor handle (no docker): start -> 2 casts -> count -> dump.
  r = cmk("cmk", "run", "demos/cmk/banana-svc.cmk", cwd=REPO, timeout=120,
          env={"CMK_SUPERVISOR": "1"})
  out = r.stdout + r.stderr
  assert "holds 2 messages" in out and "queued" in out, out[-1500:]


@pytest.mark.unit
def test_ambients_open_demo_runs(cmk):
  # the [M] side (ambients-open.cmk): `open <module>` dissolve, `*(| .. |)` inline
  # dissolve, and `import .. as` nested mount all reach the sibling probe module.
  r = cmk(
    "cmk", "run", "demos/cmk/ambients-open.cmk",
    cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"},
  )
  out = r.stdout + r.stderr
  assert "21.4C" in out and "nominal" in out, out[-1500:]
  assert "inline ambient" in out, out[-1500:]  # the `*(| .. |)` inline dissolve section


@pytest.mark.unit
def test_ambients_recipe_demo_runs(cmk):
  # the [R] side (ambients.cmk): the docker-free machine algebra -- `in host.native.sh`, `out`,
  # an in-banana `|` pipe (upcasing filter), and a captured `+` sequence.
  r = cmk(
    "cmk", "run", "demos/cmk/ambients.cmk",
    cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"},
  )
  out = r.stdout + r.stderr
  assert "A small machine" in out, out[-1500:]  # `(| echo "A small machine" |) in host.native.sh`
  assert "HI FROM A PIPE" in out, out[-1500:]  # `(| printf hi |) | (| tr a-z A-Z |)`


# --- ambient registry + resolution: the core dispatch primitives (docker-free) ----


def _probe_make(cmk, body, target):
  # plain-make probe: a throwaway wrapper that `include`s compose.mk plus `body`, then
  # runs `target`.  Exercises the SEED macros directly (no hosted/interpret path), so
  # it's fast + hermetic.  Each `@`-recipe line is a fresh shell -> no var leak between.
  wrapper = REPO / ".tmp.ambient.probe.mk"
  wrapper.write_text("include compose.mk\n" + body)
  try:
    r = cmk(target, makefile=str(wrapper), cwd=REPO, timeout=60)
    return r.returncode, r.stdout + r.stderr
  finally:
    wrapper.unlink(missing_ok=True)


def test_declare_ambient_names_only_registry(cmk):
  # `__ambients__.declare` registers only the NAME -- config (img/runner/..) is NOT denormalized into
  # the registry (it stays on the KIND instance).  Any trailing `=..` is dropped (`exp=alpine,sh` -> `exp`),
  # `__ambients__.has` tests exact membership, and a re-declare via `.require` is idempotent.
  body = (
    "$(eval $(call __ambients__.declare,bare))\n"
    "$(eval $(call __ambients__.declare,exp=alpine${comma}sh))\n"  # trailing config dropped -> `exp`
    "$(eval $(call __ambients__.require,bare))\n"  # already present -> no duplicate
    "forms:\n"
    "\t@printf 'LIST[%s]\\n' '$(__ambients__)'\n"
    "\t@printf 'HAS_BARE[%s] HAS_EXP[%s] HAS_NONE[%s]\\n' "
    "'$(call __ambients__.has,bare)' '$(call __ambients__.has,exp)' '$(call __ambients__.has,nope)'\n"
  )
  rc, out = _probe_make(cmk, body, "forms")
  assert rc == 0, out
  # names only: `exp=alpine,sh` reduced to `exp`; the list also carries the core machine ambients
  # now that `cmk.machine` self-registers; the idempotent `.require` added no `bare` duplicate.
  assert "=alpine,sh" not in out, out            # config NOT stored in the registry
  assert out.count("bare") == 2, out             # once in LIST, once in HAS_BARE -- no duplicate
  assert "HAS_BARE[bare]" in out, out
  assert "HAS_EXP[exp]" in out, out
  assert "HAS_NONE[]" in out, out               # unregistered -> empty


@pytest.mark.integration
def test_machine_default_wiring_and_entrypoint_indirection(cmk):
  # a `cmk.machine` instance: `.entrypoint` defaults LAZILY to `${self}` when there is no img (a host
  # machine's own name is its command), `.run` is the DEFERRED indirection `host.dispatch/$(entrypoint)`,
  # and `.__class__` is `cmk.machine`.  A post-mint `._entrypoint :=` override flows through to `.run`
  # (proving the indirection is live, not baked) -- the sanctioned override path (the raw `_entrypoint`).
  src = (
    "cmk.machine plain_m(| |)\n"
    "cmk.machine ov_m(| |)\n"
    "ov_m._entrypoint := bash\n"
    "foo:\n"
    "\t@printf 'entrypoint=[%s] run=[%s] cls=[%s] ovrun=[%s]\\n' "
    "\"$(plain_m.entrypoint)\" \"$(plain_m.run)\" \"$(plain_m.__class__)\" \"$(ov_m.run)\"\n"
  )
  p = REPO / ".tmp.machine.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.machine.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert "entrypoint=[plain_m]" in out, out[-1500:]        # .entrypoint lazily -> ${self} (no img)
    assert "run=[host.dispatch/plain_m]" in out, out[-1500:]  # host-command indirection
    assert "cls=[cmk.machine]" in out, out[-1500:]
    assert "ovrun=[host.dispatch/bash]" in out, out[-1500:]  # override flows to .run
  finally:
    p.unlink(missing_ok=True)


@pytest.mark.integration
def test_cbuild_noop_without_src_or_file(cmk):
  # a container's `.build` hook is always safe to call: with neither `src=` (inline
  # Dockerfile) nor `file=` (on-disk) set, it is a logged no-op -- no docker.
  src = (
    "cmk.container nobuild(| img=scratch |)\n"
    "foo:\n\t@${make} nobuild.build\n"
  )
  p = REPO / ".tmp.cbuild.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.cbuild.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "no src=/file=" in out and "noop" in out, out[-1500:]
  finally:
    p.unlink(missing_ok=True)


# --- runtime dispatch: the dissolve-route branches ----------------------------


def test_dissolve_route_unknown_kind_and_custom_hook(cmk):
  # `_ambient.dissolve.route(kind, def)`: a kind with a defined `<kind>.__open__` method (the
  # `Openable` protocol method) routes there; ANY other kind (unknown, or empty) falls back to
  # inline dissolve (eval the def body) -- it is NOT applied as a ctor.  Pins the routing table +
  # the fallback (docker-free).
  body = (
    "define payload\n"
    "dissolved_var := DISSOLVED_OK\n"
    "endef\n"
    "myknd.__open__ = $(info HOOK_RAN:$(1))$(call ambient.dissolve.inline,$(1))\n"
    "$(eval $(call ambient.dissolve, def=payload kind=totallyunknown))\n"  # unknown -> inline
    "$(eval $(call ambient.dissolve, def=payload kind=myknd))\n"           # routed to the hook
    "probe:; @printf 'var=[%s]\\n' '$(dissolved_var)'\n"
  )
  rc, out = _probe_make(cmk, body, "probe")
  assert rc == 0, out
  assert "var=[DISSOLVED_OK]" in out, out   # unknown kind -> inline dissolve (body eval'd)
  assert "HOOK_RAN:payload" in out, out     # a real `<kind>.__open__` is routed to


@pytest.mark.integration
def test_out_denied_without_host_channel(cmk):
  # Leaving a container for the host without a socket: the container's own exit hook refuses, before any docker call, so no daemon is needed.
  src = 'open cmk\ncontainer box(img=alpine entrypoint=sh)(| |)\nfoo:\n\t(| echo SHOULD_NOT_RUN |) out\n'
  p = REPO / ".tmp.outdenied.cmk"
  p.write_text(src)
  try:
    r = cmk("cmk", "run", ".tmp.outdenied.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1", "DOCKER_SOCKET": "/nonexistent.sock",
                 "__ambient__": "box", "__ambient_stack__": "host.local",
                 "__ambient_parent__": "host.local"})
    out = r.stdout + r.stderr
    assert "out denied" in out, out[-1500:]           # the escape-guard message
    assert "SHOULD_NOT_RUN" not in out, out[-1500:]   # body never executed
  finally:
    p.unlink(missing_ok=True)


@pytest.mark.needs_docker
def test_in_image_runs_body_in_real_container(docker_cmk, tmp_path):
  # `(| .. |) in container(| img=.. entrypoint=.. |)`: the inline anonymous container mints an
  # ambient and dispatches the lifted block into a REAL container via `docker.run.sh`, running the
  # body there (not on the host).  A bare image is NOT an ambient -- it must be wrapped like this.
  f = tmp_path / "in_image.cmk"
  f.write_text(
    'open cmk\n'
    'foo:\n\t(| echo IN_CONTAINER_MARK; cat /etc/os-release | grep "^ID=" |)'
    ' in container(| img=debian:bookworm-slim entrypoint=bash |)\n'
  )
  r = docker_cmk("cmk", "run", "in_image.cmk", "foo", timeout=300,
                 env={"CMK_SUPERVISOR": "1"})  # BASE_ENV's =0 breaks `cmk run <file>`
  out = r.stdout + r.stderr
  assert r.returncode == 0, out[-2000:]
  assert "IN_CONTAINER_MARK" in out, out[-2000:]
  assert "ID=debian" in out, out[-2000:]   # proves it ran INSIDE debian, not the host


@pytest.mark.needs_docker
def test_ambient_chain_crosses_the_container_boundary(docker_cmk, tmp_path):
  # without the standard-env forwarding a containerized block sees no parent at all.
  f = tmp_path / "chain_box.cmk"
  f.write_text(
    "open cmk\n"
    "container boxy(img=alpine entrypoint=sh)(| |)\n"
    "foo:\n"
    '\t(| echo "BOX_AP=[$__ambient_parent__] BOX_CUR=[$__ambient__]" |) in boxy\n'
  )
  r = docker_cmk("cmk", "run", "chain_box.cmk", "foo", timeout=300,
                 env={"CMK_SUPERVISOR": "1"})
  out = r.stdout + r.stderr
  assert r.returncode == 0, out[-2000:]
  assert "BOX_AP=[host.local]" in out, out[-2000:]
  assert "BOX_CUR=[boxy]" in out, out[-2000:]


def test_bare_anon_callform_is_grammar_error(cmk):
  # A bare anonymous banana `(| .. |)()` -- no `in`/`out`, no typed-machine constructor -- carries a
  # `()` callform trailer it cannot honor: an anonymous banana has only a string-concat algebra, no
  # callforms.  The compiler rejects it at grammar level (NotImplemented/Grammar/anon-callform); a
  # callform trailer needs a typed machine, e.g. `host.native.sh(| .. |){env}` or a named `Dockerfile`.
  # (Was: routed to `docker.lambda` as a Dockerfile lambda; that unbound-lambda path is retired, so
  # this is now a fast compile-time rejection with no docker.)
  probe = REPO / ".tmp.anon_callform.cmk"
  probe.write_text("foo:\n\t(| echo not-a-dockerfile |)()\n")
  try:
    r = cmk("cmk", "run", ".tmp.anon_callform.cmk", "foo", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})  # BASE_ENV's =0 breaks `cmk run <file>`
    out = (r.stdout + r.stderr).lower()
    assert r.returncode != 0, out[-2000:]
    assert "anon-callform" in out, out[-2000:]
    assert "string algebra" in out or "typed machine" in out, out[-2000:]
  finally:
    probe.unlink(missing_ok=True)


def test_in_host_machine_runs_docker_free(cmk):
  # UNIT-tier guard for the core `in <machine>` RUN path: a registered ambient -> its `NAME/%` target ->
  # `.run` -> host interpreter.  This is the EXACT dispatch the ambient-protocol refactor
  # (TODO-ambient-protocol.md, P2) formalizes as a per-kind `__in__`.
  # `in host.native.bash` is a host runner (no docker), so it runs fast + deterministically -- unlike
  # the sole prior RUN coverage (`in host.native.python`, which is @pytest.mark.integration).  Guards
  # P2's "byte-identical dispatch" claim in the fast loop.
  probe = REPO / ".tmp.in_bash.cmk"
  probe.write_text("demo:\n\t(| echo hi-from-bash |) in host.native.bash\n__main__: demo\n")
  try:
    r = cmk("cmk", "run", ".tmp.in_bash.cmk", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})  # BASE_ENV's =0 breaks `cmk run <file>`
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "hi-from-bash" in out, out[-1500:]
  finally:
    probe.unlink(missing_ok=True)


def test_named_receiver_in_machine_runs(cmk):
  # `&<recv> in <machine>` -- a NAMED banana/receiver (here a `&`-handle whose shape is a filled
  # `%` result) runs in a host machine.  The leading `&` marks it cmk-lang (a plain `recv in m` is
  # shell); the handle is already a def, so the lowering reuses the bare-lambda machine dispatch
  # (`_cmk.host.machine`) pointed at the name, no fresh `__lambda`.
  probe = REPO / ".tmp.recv_in.cmk"
  probe.write_text(
    "&greet <- (| echo hi @@who@@ |) % (| who=bob |)\n"
    "demo:\n\t&greet in host.native.sh\n__main__: demo\n")
  try:
    r = cmk("cmk", "run", ".tmp.recv_in.cmk", cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "hi bob" in out, out[-1500:]
  finally:
    probe.unlink(missing_ok=True)


def test_named_receiver_capture_in_machine(cmk):
  # `<lhs> <- <recv> in <machine>` -- CAPTURE the machine-run of a named receiver.  `in` is runtime,
  # so the result lands in a recipe shell var (read `$${lhs}`); the same dispatch, wrapped in a
  # backtick capture.
  probe = REPO / ".tmp.recv_cap.cmk"
  probe.write_text(
    "&greet <- (| echo hi @@who@@ |) % (| who=bob |)\n"
    "demo:\n\t&x <- greet in host.native.sh\n\t@echo \"cap=[$${x}]\"\n__main__: demo\n")
  try:
    r = cmk("cmk", "run", ".tmp.recv_cap.cmk", cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "cap=[hi bob]" in out, out[-1500:]
  finally:
    probe.unlink(missing_ok=True)


def test_add_fold_body_joins_under_handle(cmk):
  # `&`-marked `+` is a PARSE-TIME body-join (the string-algebra concat, like `%`) -- NOT the runtime
  # stdout-concat of unmarked `+`.  It rides the same `_bfold`/`.__add__`(=frag.concat) path, so `+`
  # and `%` fold together left-assoc in one pass: (echo a@@h@@ + echo b) % (h=Z) -> echo aZ / echo b.
  probe = REPO / ".tmp.add_fold.cmk"
  probe.write_text(
    "demo:\n\t&a <- (| echo x |) + (| echo y |)\n\t&a in host.native.sh\n"
    "\t&c <- (| echo a@@h@@ |) + (| echo b |) % (| h=Z |)\n\t&c in host.native.sh\n__main__: demo\n")
  try:
    r = cmk("cmk", "run", ".tmp.add_fold.cmk", cwd=REPO, timeout=120, env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "x" in out and "y" in out, out[-1500:]      # body-join ran both lines
    assert "aZ" in out and "\nb" in out, out[-1500:]   # `+` then `%` composed in one fold
  finally:
    probe.unlink(missing_ok=True)


def test_machine_and_namespace_conform_to_ambient_protocol(cmk):
  # ambient-protocol P2+P5: the `cmk.ambient` CLASS was demoted to `protocol Ambient` (MEMBERSHIP --
  # `.__ambient_parent__`).  A machine mixes it via `bases=Ambient` (nominal + structural conformance).
  # A `namespace` -- a DIFFERENT metaclass (`cmk.constructor`) that a class base could never span -- now
  # conforms STRUCTURALLY too (its ctor sets `.__ambient_parent__`): P5 RESOLVES the machine-vs-namespace
  # asymmetry.  The namespace joins `__ambients__` like any other ambient, because its ctor also stamps
  # the entry and reenter doors -- so `in <ns>` routes, and an outward move can land on the group.
  probe = REPO / ".tmp.ambient_proto.cmk"
  probe.write_text(
    "from cmk import machine, namespace\n"
    "machine box(| img=alpine |)\n"
    "namespace ns[| foo:; @true |]\n"
    "demo:\n"
    "\t@printf 'isa=[%s] pbox=[%s] pns=[%s] nsreg=[%s] abs=[%s]\\n' "
    "'$(call isinstance,box,Ambient)' '$(call Ambient.provided_by,box)' "
    "'$(call Ambient.provided_by,ns)' '$(call __ambients__.has,ns)' '$(Ambient.abstract)'\n"
    "__main__: demo\n"
  )
  try:
    r = cmk("cmk", "run", ".tmp.ambient_proto.cmk", cwd=REPO, timeout=120,
            env={"CMK_SUPERVISOR": "1"})
    out = r.stdout + r.stderr
    assert r.returncode == 0, out[-1500:]
    assert "isa=[1]" in out, out[-1500:]                 # machine IS-A Ambient (nominal, via bases=)
    assert "pbox=[1]" in out, out[-1500:]                # + structural conformance
    assert "pns=[1]" in out, out[-1500:]                 # namespace conforms too (asymmetry RESOLVED)
    assert "nsreg=[ns]" in out, out[-1500:]              # + registered, so `in <ns>` routes
    assert "abs=[__all__ __ambient_parent__ __dir__ __name__]" in out, out[-1500:]
  finally:
    probe.unlink(missing_ok=True)
