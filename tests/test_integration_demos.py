"""End-to-end tests for the plain-Makefile demos under `demos/*.mk`.

These exercise the `run_plain_demo` fixture (conftest.py), which runs a real
`demos/*.mk` directly via `make -f demos/<name>.mk <target>` (default
`__main__`) -- the same plain `make -f` path the demos' shebang uses (NOT
`mk.interpret!`, which is only for the CMK-language demos covered in
test_integration_cmk.py). Runs from the repo root so `include compose.mk` and
`demos/data/*` resolve, and via docker_cmk so anything a demo dispatches is
label/project-scoped and swept on teardown.

The cases below are the *lightweight* demos with deterministic stdout. `log.*`
output goes to stderr, so assertions target the demos' `echo`/`printf` lines.
Most are host-only (only compose.mk + host shell, no container); a couple are
marked needs_docker because they reflect (mkparse runs in a container) or use
jb/jq (which fall back to containers when absent on the host). Heavy demos
(external interpreters, docker dispatch, TUI, network) are intentionally
excluded.
"""

import pytest

pytestmark = [pytest.mark.integration]


def test_demo_no_include(run_plain_demo):
  # Pure Make (does NOT include compose.mk): clean/build/test echo banners.
  r = run_plain_demo("demos/no-include.mk")
  assert r.ok, r.stderr
  assert "cleaning" in r.stdout
  assert "building" in r.stdout
  assert "testing" in r.stdout


def test_demo_parsing_parameters(run_plain_demo):
  # bind.args.from_params: positional args from both / and , delimited targets.
  r = run_plain_demo("demos/parsing-parameters.mk")
  assert r.ok, r.stderr
  assert "1st=one 2nd=two 3rd=three" in r.stdout


def test_demo_partials(run_plain_demo):
  # mk.unpack.arg + __flux.partial__: adder/1,3=4, add7/3=10, add2/10=12.
  r = run_plain_demo("demos/partials.mk")
  assert r.ok, r.stderr
  for expected in ("4", "10", "12"):
    assert expected in r.stdout.split(), r.stdout


def test_demo_kwarg_parsing_env(run_plain_demo):
  # bind.args.from_env: `shape` keeps its exported value, `color` takes default.
  r = run_plain_demo("demos/kwarg-parsing-2.mk")
  assert r.ok, r.stderr
  assert "shape=circle color=blue" in r.stdout


def test_demo_kwarg_parsing_factory(run_plain_demo):
  # mk.unpack.kwargs target-factory: targets generated per shape, then run.
  r = run_plain_demo("demos/kwarg-parsing-3.mk")
  assert r.ok, r.stderr
  assert "A default triangle /default data/" in r.stdout
  assert "A yellow circle /single quotes only/" in r.stdout
  assert "A black square /default data/" in r.stdout


@pytest.mark.needs_docker
def test_demo_flux_star(run_plain_demo):
  # `flux.star/test` reflects the makefile (mkparse runs in a container) to
  # pattern-dispatch every test.* target -- and only those.
  r = run_plain_demo("demos/flux.star.mk")
  assert r.ok, r.stderr
  assert "1" in r.stdout and "2" in r.stdout and "3" in r.stdout
  assert "never called" not in r.stdout


@pytest.mark.needs_docker
def test_demo_structured_io(run_plain_demo):
  # jb (emit) | jq (consume) across `${make}` stages -- plain-make twin of the
  # structured-io.cmk case. jb/jq fall back to containers when not on host.
  r = run_plain_demo("demos/structured-io.mk")
  assert r.ok, r.stderr
  assert "val" in r.stdout
