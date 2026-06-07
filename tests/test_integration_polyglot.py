"""Integration test for polyglot.import (interpreter-container scaffolding).

polyglot.import (without `bind`) scaffolds a containerized interpreter:
`<ns>.interpreter.base` runs the interpreter image, and `<ns>.interpreter/<cmd>`
runs a command through it. With a plain image + entrypoint=none the command runs
directly. Driven via the `project` fixture (docker-labeled, swept on teardown).
"""

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]


def test_polyglot_import_interpreter(project):
  # Covers the generated <ns>.interpreter and <ns>.interpreter.base templates.
  project.load("polyglot-import")
  r = project.run("myp.interpreter/whoami")
  assert r.ok, r.stderr
  assert "root" in r.stdout
  assert project.run("myp.interpreter.base").ok
