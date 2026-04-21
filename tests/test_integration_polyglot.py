"""Integration test: a code-object with img+entrypoint mints a machine and runs in it.

`code` (with an `img`/`entrypoint`, no `bind`) mints a `<def>.machine` (a plain `cmk.machine`)
and binds the code-object to it; running the code-object runs its body inside the image via the
machine's call dispatch.  Driven via the `project` fixture (docker-labeled, swept on teardown).
"""

import pytest

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.plugin,
]


def test_polyglot_import_interpreter(project):
  # The code-object (whoami body) runs INSIDE alpine (root) via the minted machine; the
  # machine's `.build` hook is a noop (no src=/file=).
  project.load("polyglot-import")
  r = project.run("myp")
  assert r.ok, r.stderr
  assert "root" in r.stdout                          # whoami ran INSIDE alpine (root)
  assert project.run("mycode.machine.build").ok      # the minted machine's build hook
