"""End-to-end tests of the shipped `cli.subcommands` demo clients.

Two *equivalent* zero-config clients of the reusable `cli.subcommands` engine: a
`greet` CLI with non-parametric (`world`, `me`) and parametric (`hello`) handlers,
namespace/subcommands/default all auto-detected, with NO edit to compose.mk core:

  * demos/subcommands.mk      : plain make, `greet:; $(call cli.subcommands.enter)`
    (single default namespace `.greet`)
  * demos/cmk/subcommands.cmk : CMK-lang, the `ᝏsubcommands` decorator, demonstrating
    the namespace MRO (handlers split across the `├` and `╰` namespaces)

Every test runs against BOTH (the `greet` fixture is parametrized), so the CMK
decorator is proven equivalent to the macro form.  Each is run supervised via
`./compose.mk mk.interpret[!] <file> <goals>` (a dispatcher needs the supervisor
for its yield/interrupt epilogue; hence CMK_SUPERVISOR=1, overriding the harness
default of 0).

The `test_*_hooks_on` case is the key reusability proof: with the pre/post-hook
rewrite enabled, `greet`'s goals are decorated (flux.pre/greet ...), and the demo
STILL parses its tail correctly thanks to robust anchor-based capture.
"""

from pathlib import Path

import pytest

pytestmark = pytest.mark.integration

REPO = Path(__file__).resolve().parent.parent

# A dispatcher's single yield needs the supervisor (harness default is 0).
SUP = {"CMK_SUPERVISOR": "1"}


@pytest.fixture(
  params=[
    ("demos/subcommands.mk", "mk.interpret"),  # plain-make macro form
    ("demos/cmk/subcommands.cmk", "mk.interpret!"),  # CMK-lang decorator form
  ],
  ids=["mk", "cmk"],
)
def greet(request, cmk):
  demo, interpret = request.param

  def run(*args, **env):
    return cmk(interpret, demo, "greet", *args, env={**SUP, **env}, cwd=REPO)

  return run


def test_demo_non_parametric_world(greet):
  # `.greet.world` takes no stem -> routed bare.
  r = greet("world")
  assert r.ok, r.stderr
  assert "hello world" in r.stdout


def test_demo_non_parametric_me(greet):
  # `.greet.me` (non-parametric) prints the env USER.
  r = greet("me", USER="tester")
  assert r.ok, r.stderr
  assert "hello tester" in r.stdout


def test_demo_parametric_hello(greet):
  r = greet("hello", "bob")
  assert r.ok, r.stderr
  assert "hello, bob!" in r.stdout


def test_demo_parametric_remaining_args_in_argv(greet):
  # args after the stem reach the parametric handler in $argv.
  r = greet("hello", "bob", "extra")
  assert r.ok, r.stderr
  assert "hello, bob! (argv=extra)" in r.stdout


def test_demo_unknown_subcommand_errors(greet):
  # an unrecognized first word errors (greet's default `world` is non-parametric, so
  # there's no positional for the word to fill -- it's a typo'd subcommand, not an arg).
  r = greet("zzz")
  assert not r.ok
  assert "unknown subcommand" in r.stderr.lower()
  # throws the recognizable symbolic token (cf. CMK_INCLUDE_MISSING).
  assert "CMK_UNKNOWN_SUBCOMMAND" in r.stderr


def test_demo_usage_marks_parametric(greet):
  # no subcommand -> multi-line usage; parametric subs annotated `<arg>`, not others.
  r = greet()
  assert r.ok, r.stderr
  lines = r.stderr.splitlines()
  hello_line = next(
    line for line in lines if "hello" in line and "usage" not in line
  )
  world_line = next(line for line in lines if "world" in line)
  assert "<arg>" in hello_line  # parametric
  assert "<arg>" not in world_line  # non-parametric


def test_demo_zero_config_with_hooks_on(greet):
  # The reusability proof: with the pre/post-hook rewrite ON, `greet`'s goals are
  # decorated, yet robust capture recovers the tail with NO skip-list entry.
  r = greet("hello", "bob", CMK_DISABLE_HOOKS="0")
  assert r.ok, r.stderr
  assert "hello, bob!" in r.stdout


# --- OOP / MRO demos: namespace search-order simulates class inheritance ------
# demos/oop.{mk,cmk}: a `pet` CLI with namespace MRO `.puppy .dog
# .animal`.  `speak` is defined in all three (most-derived `.puppy` wins); `fetch`
# only in `.dog`; `legs`/`describe` only in the base `.animal`, both inherited.


@pytest.fixture(
  params=[
    ("demos/oop.mk", "mk.interpret"),
    ("demos/cmk/oop.cmk", "mk.interpret!"),
  ],
  ids=["mk", "cmk"],
)
def pet(request, cmk):
  demo, interpret = request.param

  def run(*args, **env):
    return cmk(interpret, demo, "pet", *args, env={**SUP, **env}, cwd=REPO)

  return run


def test_oop_override_most_derived_wins(pet):
  # speak is defined in all three namespaces; `.puppy` (most-derived) wins.
  r = pet("speak")
  assert r.ok, r.stderr
  assert "yip!" in r.stdout


def test_oop_inherits_from_middle_class(pet):
  # fetch is only in `.dog` -> inherited.
  r = pet("fetch")
  assert r.ok, r.stderr
  assert "fetches the ball" in r.stdout


def test_oop_inherits_from_base_class(pet):
  # legs is only in `.animal` (the base) -> inherited through the MRO.
  r = pet("legs")
  assert r.ok, r.stderr
  assert r.stdout.strip() == "4"


def test_oop_inherits_parametric(pet):
  # describe/% is only in `.animal` -> inherited, and parametric (takes the stem).
  r = pet("describe", "rex")
  assert r.ok, r.stderr
  assert "rex is a kind of animal" in r.stdout


# --- NESTED subcommands: a handler that is ITSELF a `cli.subcommands.enter` -------
# demos/subcommands-nested.mk: `app` -> {status (leaf), db (sub-group)} where `db` ->
# {migrate (leaf), seed/% (parametric)}.  Proves a multi-word path threads down through
# each level: the engine forwards a dispatched handler's remaining words in $argv (the
# command line is just the handler name), and a nested `enter` reads them from there.


@pytest.fixture
def app(cmk):
  def run(*args, **env):
    return cmk(
      "mk.interpret",
      "demos/subcommands-nested.mk",
      "app",
      *args,
      env={**SUP, **env},
      cwd=REPO,
    )

  return run


def test_nested_leaf_at_top_level(app):
  # `status` is a plain leaf of the top group -- the non-nested baseline.
  r = app("status")
  assert r.ok, r.stderr
  assert "app status ok" in r.stdout


def test_nested_dispatch_two_levels(app):
  # `app db migrate` threads through the `db` sub-group to its `migrate` leaf.
  r = app("db", "migrate")
  assert r.ok, r.stderr
  assert "db migrate (argv=)" in r.stdout


def test_nested_args_thread_to_depth(app):
  # a trailing arg survives the descent: it reaches the depth-2 handler in $argv.
  r = app("db", "migrate", "force")
  assert r.ok, r.stderr
  assert "db migrate (argv=force)" in r.stdout


def test_nested_parametric_at_depth(app):
  # a PARAMETRIC handler nested one level down still gets its stem.
  r = app("db", "seed", "users")
  assert r.ok, r.stderr
  assert "db seed users" in r.stdout


def test_nested_subgroup_bare_shows_usage(app):
  # `app db` with no further sub -> the sub-group's own usage (not the top group's).
  r = app("db")
  assert r.ok, r.stderr
  assert "db" in r.stderr and "migrate" in r.stderr and "seed" in r.stderr


def test_nested_dispatch_has_no_supervisor_noise(app):
  # A nested `enter` runs under CMK_SUPERVISOR=0; its `mk.yield` must NOT fire a doomed
  # `mk.interrupt` (which would log "Supervisor is disabled" + a spurious *** Error on stderr).
  r = app("db", "migrate")
  assert r.ok, r.stderr
  assert "db migrate" in r.stdout
  noise = ("Supervisor is disabled", "mk.interrupt/SIGINT", "] Error ")
  assert not any(n in r.stderr for n in noise), r.stderr
