"""Packaging targets: mk.fork.*, mk.self, mk.pkg (docs/demos/packaging.md.j2).

  * mk.fork.guest  -- embeds a Makefile as the "guest" section of compose.mk,
    returning a self-contained forked source on stdout. Pure text, no docker.
  * mk.self        -- wraps a dockerized `makeself` to turn (archive + entrypoint
    script) into a self-extracting executable.
  * mk.pkg/<tgt>   -- packages a make target as a single-file executable (mk.self
    under the hood, bundling compose.mk).

These tests now EXECUTE the produced artifacts (not just validate the Makeself
header). The makeself entrypoint's stdout IS surfaced when its argv is
space-separated (e.g. `make ... -f compose.mk flux.ok`); the pitfall is an
inner-quoted `sh -c "..."` whose quotes are lost crossing the make->docker->makeself
layers -- so the mk.self exec test uses a quote-free `echo` entrypoint.

Coverage: a forked Makefile, a raw makeself archive, packaging a built-in target,
the same under a GLOBAL/on-PATH install, and packaging a `.cmk` via `mk.interpret!`
(the interpret branch of mk.pkg.root). The makeself-backed cases need docker.
"""

import os
import re
import subprocess

import pytest

pytestmark = pytest.mark.integration

_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_artifact(argv, cwd=None, timeout=300):
  """Execute a produced artifact (a makeself binary, or `make -f <fork>`), and
  return (returncode, ANSI-stripped stdout+stderr). Color/CI noise is suppressed;
  CMK_SUPERVISOR is left at its default so a packaged `mk.interpret!` works."""
  if isinstance(argv, (str, os.PathLike)):
    argv = [str(argv)]
  else:
    argv = [str(a) for a in argv]
  env = {
    **os.environ,
    "NO_COLOR": "1",
    "TERM": "dumb",
    "GITHUB_ACTIONS": "false",
  }
  p = subprocess.run(
    argv,
    cwd=str(cwd) if cwd else None,
    env=env,
    capture_output=True,
    text=True,
    timeout=timeout,
  )
  return p.returncode, _ANSI.sub("", p.stdout + p.stderr)


def test_mk_fork_guest_executes(cmk, tmp_path):
  # Fork a tiny guest Makefile into compose.mk; the forked source embeds the guest
  # target AND the full stdlib (the `include compose.mk` is stripped). Then RUN the
  # fork standalone -- it needs no compose.mk on disk.
  (tmp_path / "guest.mk").write_text(
    "hello:\n\t@echo FORK-EXEC-9f\n__main__: hello\n"
  )
  r = cmk("mk.fork.guest/guest.mk")
  assert r.ok, r.stderr
  assert "FORK-EXEC-9f" in r.stdout, "guest target not embedded in fork"
  assert "flux.ok" in r.stdout, "forked source is missing the standard library"
  forked = tmp_path / "forked.mk"
  forked.write_text(r.stdout)
  # execute the guest target through the fork (self-contained: no compose.mk here)
  rc, out = _run_artifact(["make", "-f", str(forked), "hello"], cwd=tmp_path)
  assert rc == 0, out
  assert "FORK-EXEC-9f" in out, out
  # and an embedded stdlib target still works in the fork
  rc2, out2 = _run_artifact(
    ["make", "-f", str(forked), "flux.ok"], cwd=tmp_path
  )
  assert rc2 == 0, out2
  assert "flux.ok" in out2, out2


@pytest.mark.needs_docker
def test_mk_self_builds_and_executes(project):
  # mk.self bundles a dir + an entrypoint into a self-extracting binary; assert it
  # is a valid Makeself archive AND that running it executes the entrypoint.
  project.seed_compose_mk()
  project.write("payload/marker.txt", "MARKER-OK\n")
  r = project.run(
    "mk.self",
    env={
      "archive": "payload",
      "bin": "archive.run",
      "script": "echo",  # quote-free entrypoint (see module docstring)
      "script_args": "SELF-EXEC-9z",
    },
    timeout=420,
  )
  assert r.ok, r.stderr
  out_bin = project.dir / "archive.run"
  assert out_bin.exists(), "mk.self did not produce the executable"
  assert b"Makeself" in out_bin.read_bytes()[:4096]
  rc, out = _run_artifact(out_bin, cwd=project.dir)
  assert rc == 0, out
  assert "SELF-EXEC-9z" in out, out


@pytest.mark.needs_docker
def test_mk_pkg_packages_and_runs_builtin(project):
  # Package a built-in (flux.ok) as a standalone executable, then run it: the
  # packaged target actually executes (uses the bundled compose.mk).
  project.seed_compose_mk()
  r = project.run("mk.pkg/flux.ok", env={"bin": "flux.ok.bin"}, timeout=420)
  assert r.ok, r.stderr
  out_bin = project.dir / "flux.ok.bin"
  assert out_bin.exists(), "mk.pkg did not produce the executable"
  assert b"Makeself" in out_bin.read_bytes()[:4096]
  rc, out = _run_artifact(out_bin, cwd=project.dir)
  assert rc == 0, out
  assert "flux.ok" in out, out  # the packaged target ran


@pytest.mark.needs_docker
def test_mk_pkg_under_global_install_runs(staged_global):
  # Package a built-in with compose.mk staged OUTSIDE the workspace (global/on-PATH
  # install), then run the produced binary on this host. Guards that mk.pkg works at
  # all under a global install. (Cross-machine portability of the non-interpret
  # branch is a separate caveat -- its embedded `-f` is the host abspath.)
  r = staged_global("mk.pkg/flux.ok", bin="g.bin")
  assert r.returncode == 0, r.stderr
  out_bin = staged_global.workspace / "g.bin"
  assert out_bin.exists(), "global mk.pkg did not produce the executable"
  rc, out = _run_artifact(out_bin, cwd=staged_global.workspace)
  assert rc == 0, out
  assert "flux.ok" in out, out


@pytest.mark.needs_docker
def test_mk_pkg_interpret_cmk_runs(project):
  # Package a `.cmk` via the mk.interpret! / interpret branch of mk.pkg.root: the
  # binary is `bash <bundled-compose.mk> mk.interpret! <app.cmk>`, so running it
  # transpiles+executes the bundled CMK. (This exercises the interpret-branch fix
  # that uses the bundled basename, not a host `./compose.mk` path.)
  project.seed_compose_mk()
  project.write("app.cmk", "demo:\n\t@echo CMK-PKG-4q\n__main__: demo\n")
  r = project.run(
    "mk.interpret!",
    "app.cmk",
    "mk.pkg.root",
    env={"CMK_SUPERVISOR": "1", "bin": "app.bin", "archive": "app.cmk"},
    timeout=420,
  )
  assert r.ok, r.stderr
  out_bin = project.dir / "app.bin"
  assert out_bin.exists(), (
    "interpret-branch mk.pkg did not produce the executable"
  )
  assert b"Makeself" in out_bin.read_bytes()[:4096]
  rc, out = _run_artifact(out_bin, cwd=project.dir)
  assert rc == 0, out
  assert "CMK-PKG-4q" in out, out
