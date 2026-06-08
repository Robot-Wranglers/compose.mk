"""Integration tests for self-parse reflection targets.

mk.parse / mk.namespace.filter / *.help all route through `mkparse`, which runs
in a container and parses the *current* makefile from the mounted cwd. They
work only from a project dir whose Makefile includes compose.mk (so the file is
in the mount and ${MAKEFILE} is relative) - i.e. the `project` scaffold. Hence
integration + needs_docker, not unit (the unit attempts failed because an
absolute makefile path isn't inside the mkparse container mount).
"""

import json

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]

# A project Makefile that includes compose.mk plus two local targets.
DEMO = "demo.alpha:; @true\ndemo.beta:; @true"


def test_mk_namespace_filter(project):
  project.makefile(DEMO)
  r = project.run("mk.namespace.filter/demo.")
  assert r.ok, r.stderr
  assert "demo.alpha" in r.stdout
  assert "demo.beta" in r.stdout


@pytest.mark.parametrize(
  "target,needle",
  [
    ("mk.help", "mk.clean"),
    ("io.help", "io.echo"),
    ("stream.help", "stream.echo"),
    ("flux.help", "flux.ok"),
    ("docker.help", "docker.images"),
  ],
)
def test_namespace_help(project, target, needle):
  # *.help == mk.namespace.filter/<ns>. - lists the compose.mk targets the
  # scaffolded project inherits via `include compose.mk`.
  project.makefile(DEMO)
  r = project.run(target)
  assert r.ok, r.stderr
  assert needle in r.stdout


def test_mk_parse_targets(project):
  project.makefile(DEMO)
  r = project.run("mk.parse.targets/Makefile")
  assert r.ok, r.stderr
  assert "demo.alpha" in r.stdout


def test_mk_parse_full_json(project):
  project.makefile(DEMO)
  r = project.run("mk.parse/Makefile")
  assert r.ok, r.stderr
  assert "demo.alpha" in json.loads(r.stdout)


def test_flux_star_runs_matching_targets(project):
  # flux.star/<prefix> = mk.namespace.filter (mkparse/docker) -> run each match
  # via flux.apply. (flux.match is the same-line alias.)
  project.makefile("demo.alpha:; @echo ALPHA-RAN\ndemo.beta:; @echo BETA-RAN")
  r = project.run("flux.star/demo.")
  assert r.ok, r.stderr
  assert "ALPHA-RAN" in r.stdout
  assert "BETA-RAN" in r.stdout


@pytest.mark.parametrize("target", ["mk.targets", "mk.targets.simple"])
def test_mk_targets_lists_standalone(project, target):
  # mk.targets uses `mkparse --shallow`, which EXCLUDES included targets - so
  # point it at a standalone makefile (a driver Makefile provides the target).
  project.makefile("")
  project.write("plain.mk", "build:; @true\ntest:; @true\nclean:; @true\n")
  r = project.run(f"{target}/plain.mk")
  assert r.ok, r.stderr
  assert {"build", "test", "clean"} <= set(r.stdout.split())


def test_mk_targets_filter(project):
  # mk.targets.filter/<prefix> greps the local makefile's targets.
  project.makefile("build:; @true\ntestme:; @true")
  r = project.run("mk.targets.filter/build")
  assert r.ok, r.stderr
  assert "build" in r.stdout.split()


def test_mk_parse_block(project):
  # Pulls doc-blocks matching a pattern from a makefile (here, compose.mk).
  project.makefile("")
  r = project.run("mk.parse.block/compose.mk", env={"pattern": "TUI"})
  assert r.ok, r.stderr
  assert "TUI" in r.stdout


@pytest.mark.parametrize(
  "target", ["mk.targets.parametric", "mk.targets.filter.parametric/x"]
)
def test_mk_targets_parametric_runs(project, target):
  # --shallow doesn't surface local parametric targets, so these are empty
  # here; assert they run cleanly (target coverage).
  project.makefile("widget/%:; @true")
  r = project.run(target)
  assert r.ok, r.stderr
