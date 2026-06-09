"""Packaging targets: mk.fork.*, mk.self, mk.pkg (docs/demos/packaging.md.j2).

  * mk.fork.guest  -- embeds a Makefile as the "guest" section of compose.mk,
    returning the forked source on stdout. Pure text rewriting, no docker.
  * mk.self        -- wraps a dockerized `makeself` to turn (archive + entrypoint
    script) into a self-extracting executable.
  * mk.pkg/<tgt>   -- packages a make target as a single-file executable (mk.self
    under the hood, bundling compose.mk).

These are intentionally basic. The docs demo mk.pkg with stream.img (chafa),
tux.demo, and ansible.adhoc; per request we avoid ansible/tux entirely and
package the trivial built-in `flux.ok` instead. The makeself-backed targets need
docker; mk.fork.* does not.

The makeself targets assert the produced binary is a valid Makeself archive
rather than executing it: makeself runs `--quiet`, so the bundled entrypoint's
stdout isn't reliably surfaced for assertion.
"""

import pytest

pytestmark = pytest.mark.integration


def test_mk_fork_guest_embeds_makefile(cmk):
  # Fork a tiny guest Makefile into compose.mk; the forked source should contain
  # the guest's targets AND the full standard library. Pure text, no docker.
  guest = "hello:\n\t@echo HELLO-FROM-GUEST\n__main__: hello\n"
  r = cmk("mk.fork.guest", stdin=guest)
  assert r.ok, r.stderr
  assert "HELLO-FROM-GUEST" in r.stdout, "guest target not embedded in fork"
  assert "flux.ok" in r.stdout, "forked source is missing the standard library"


@pytest.mark.needs_docker
def test_mk_self_builds_self_extracting_archive(project):
  # mk.self bundles a dir + an entrypoint script into a self-extracting binary.
  project.seed_compose_mk()
  project.write("payload/marker.txt", "MARKER-OK\n")
  r = project.run(
    "mk.self",
    env={
      "archive": "payload",
      "bin": "archive.run",
      "script": 'sh -c "true"',
    },
    timeout=420,
  )
  assert r.ok, r.stderr
  out = project.dir / "archive.run"
  assert out.exists(), "mk.self did not produce the executable"
  # a real makeself self-extracting archive identifies itself in its header
  assert b"Makeself" in out.read_bytes()[:4096]


@pytest.mark.needs_docker
def test_mk_pkg_packages_builtin_target(project):
  # Package a trivial built-in (flux.ok) as a standalone executable. (The docs
  # use stream.img / tux.demo / ansible.adhoc here; we deliberately don't.)
  project.seed_compose_mk()
  r = project.run("mk.pkg/flux.ok", env={"bin": "flux.ok.bin"}, timeout=420)
  assert r.ok, r.stderr
  out = project.dir / "flux.ok.bin"
  assert out.exists(), "mk.pkg did not produce the executable"
  assert b"Makeself" in out.read_bytes()[:4096]
