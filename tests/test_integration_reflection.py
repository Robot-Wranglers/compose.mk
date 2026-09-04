"""Integration tests for self-parse reflection targets.

mk.parse / mk.namespace.filter / *.help all route through the `mkparse` seam,
now a native awk+jq engine folded into compose.mk (`${_mkp.native}`; the old
containerized `ghcr.io/.../mk.parse` is gone). They parse the *current* makefile
and so run from a project dir whose Makefile includes compose.mk - i.e. the
`project` scaffold. Kept integration + needs_docker because the scaffold drives
via the docker_cmk fixture; the parse itself no longer needs a container.
"""

import json
import re

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]

# A project Makefile that includes compose.mk plus two local targets.
DEMO = "demo.alpha:; @true\ndemo.beta:; @true"

# A richer scaffold exercising every facet of the mk.parse contract: a
# documented target (two `@#` lines), a plain target, a `.`-private and a
# `_`-"private" target (the two are treated differently, see below), a
# parametric target, and a prereq edge.  `demo.alpha` is the first body line so
# it sits at a known, small line number.
DEMO_RICH = (
  "demo.alpha:; @true\n"
  "\t@# The alpha docstring.\n"
  "\t@# Second line.\n"
  "demo.beta: demo.alpha\n"
  "\t@true\n"
  ".demo.hidden:; @true\n"
  "_demo.under:; @true\n"
  "demo.widget/%:; @true\n"
  "\t@# A parametric widget.\n"
)

# Keys every parsed target object must carry (the shape docs-render + the help
# targets read).  `alias`/`primary` drive the docs "Alias for <primary>" line;
# `name`/`header`/`lineno` drive the source links.
CONTRACT_KEYS = {
  "name",
  "file",
  "header",
  "lineno",
  "parametric",
  "type",
  "docs",
  "prereqs",
  "local",
  "private",
  "alias",
  "primary",
}

_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _strip_ansi(s):
  return _ANSI.sub("", s)


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
    ("stage.help", "stage.file"),
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
  r = project.run("mk.parse.doc_block/compose.mk", env={"pattern": "TUI"})
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


# ---------------------------------------------------------------------------
# mk.parse contract spec
#
# The tests below pin the observable behaviour of the native awk+jq `mk.parse`
# engine (the `${_mkp.native}` seam) that compose.mk's help/reflection targets
# and the docs-render macros depend on: the per-target JSON shape, the flag
# projections (`--public`/`--names-only`/`--shallow`/`--prefix`), docstring and
# alias extraction, and cblocks. A change to the engine that breaks any consumer
# surfaces here as a failing assertion to review.
# ---------------------------------------------------------------------------


def _parse(project, body=DEMO_RICH):
  """Scaffold `body`, run `mk.parse/Makefile`, return the parsed JSON dict."""
  project.makefile(body)
  r = project.run("mk.parse/Makefile")
  assert r.ok, r.stderr
  return json.loads(r.stdout)


def test_mk_parse_target_object_schema(project):
  # Every parsed target is an object carrying the full contract key-set.
  data = _parse(project)
  alpha = data["demo.alpha"]
  assert CONTRACT_KEYS <= set(alpha), sorted(set(alpha))
  assert alpha["file"] == "Makefile"
  assert isinstance(alpha["lineno"], int) and alpha["lineno"] >= 0
  assert alpha["parametric"] is False
  assert alpha["local"] is True
  assert alpha["private"] is False
  assert isinstance(alpha["docs"], list)
  assert isinstance(alpha["prereqs"], list)


def test_mk_parse_captures_docstrings(project):
  # `@#` comment lines under a target become its `docs` (marker stripped,
  # source order kept). This is what `help/<t>` and the docs render consume.
  data = _parse(project)
  docs = [d.strip() for d in data["demo.alpha"]["docs"]]
  assert docs == ["The alpha docstring.", "Second line."]


def test_mk_parse_records_prereqs(project):
  # `demo.beta: demo.alpha` -- the dependency edge is surfaced in `prereqs`.
  data = _parse(project)
  assert "demo.alpha" in data["demo.beta"]["prereqs"]


def test_mk_parse_alias_primary(project):
  # A multi-target line (`a b c:`) shares one stanza; the parser picks one
  # `primary` and marks the rest `alias`, all pointing at the same `primary`.
  # This is what the docs render reads to emit "Alias for <primary>".
  project.makefile("")
  project.write("aliases.mk", "build test check:; @true\n")
  r = project.run("mk.parse/aliases.mk")
  assert r.ok, r.stderr
  data = json.loads(r.stdout)
  primaries = {k: data[k]["primary"] for k in ("build", "test", "check")}
  assert len(set(primaries.values())) == 1  # all point at one primary
  (primary,) = set(primaries.values())
  assert data[primary]["alias"] is False
  assert all(data[k]["alias"] is True for k in primaries if k != primary)


def test_mk_parse_parametric_target_flag(project):
  # Parametric (`%`) targets are flagged; the name/header keep the `%` form.
  data = _parse(project)
  widget = data["demo.widget/%"]
  assert widget["parametric"] is True
  assert widget["name"] == "demo.widget/%"
  assert data["demo.alpha"]["parametric"] is False


def test_mk_parse_public_private_semantics(project):
  # `mk.parse.targets` passes `--public --names-only`. The public filter drops
  # ONLY `.`-prefixed names; a leading underscore is NOT treated as private.
  project.makefile(DEMO_RICH)
  r = project.run("mk.parse.targets/Makefile")
  assert r.ok, r.stderr
  names = set(r.stdout.split())
  assert "demo.alpha" in names
  assert "_demo.under" in names  # underscore stays public
  assert ".demo.hidden" not in names  # dot is filtered


def test_mk_namespace_filter_is_prefix_not_substring(project):
  # `mk.namespace.filter/<p>` filters by prefix (startswith), not substring.
  project.makefile(DEMO_RICH)
  r = project.run("mk.namespace.filter/demo.a")
  assert r.ok, r.stderr
  names = r.stdout.split()
  assert "demo.alpha" in names
  assert "demo.beta" not in names


def test_mk_targets_shallow_excludes_included(project):
  # `mk.targets` (shallow, single-file) surfaces the driver's own local targets
  # but never targets pulled in via `include`.
  project.makefile("")
  project.write("lib.mk", "lib.included:; @true\n")
  project.write("driver.mk", "include lib.mk\nlocal_one:; @true\n")
  r = project.run("mk.targets/driver.mk")
  assert r.ok, r.stderr
  names = r.stdout.split()
  assert "local_one" in names
  assert "lib.included" not in names


def test_mk_targets_shallow_handles_dotted_names(project):
  # The native shallow scanner surfaces dotted target names (`foo.bar`), unlike
  # the old container scanner which silently dropped anything with a `.`.
  project.makefile("")
  project.write("mixed.mk", "plain:; @true\ndotted.name:; @true\n")
  r = project.run("mk.targets/mixed.mk")
  assert r.ok, r.stderr
  names = r.stdout.split()
  assert "plain" in names
  assert "dotted.name" in names


def test_mk_parse_block_pattern_miss(project):
  # cblocks with a pattern that matches no doc-block yields no block content
  # (complements test_mk_parse_block, which asserts a hit).
  project.makefile("")
  r = project.run(
    "mk.parse.doc_block/compose.mk",
    env={"pattern": "NoSuchDocBlock_zzz"},
  )
  assert r.ok, r.stderr
  assert "NoSuchDocBlock_zzz" not in r.stdout


@pytest.mark.parametrize(
  "target", ["help/demo.alpha", "mk.help.target/demo.alpha"]
)
def test_help_target_surfaces_docstring(project, target):
  # End-to-end: the help renderers (markdown+preview via mkparse) show the
  # target name and its captured `@#` docstring text.
  project.makefile(DEMO_RICH)
  r = project.run(target)
  assert r.ok, r.stderr
  out = _strip_ansi(r.stdout)
  assert "demo.alpha" in out
  assert "The alpha docstring." in out


def test_help_includes_hosted_targets(project):
  # `flux.help` surfaces both seed-level targets (`flux.noop`) and ones that
  # live in compose.mk's `define __hosted__` self-hosting cache (`flux.ok`).
  # (The old container parser missed the hosted set; the native engine sees it.)
  project.makefile(DEMO)
  r = project.run("flux.help")
  assert r.ok, r.stderr
  names = r.stdout.split()
  assert "flux.noop" in names  # seed target
  assert "flux.ok" in names  # hosted target
