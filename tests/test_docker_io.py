"""Docker-gated io.* targets.

io targets that need a tool compose.mk provides via a container (e.g. figlet).
Output goes to stderr, so these assert exit status.
"""

import pytest

pytestmark = [pytest.mark.docker, pytest.mark.needs_docker]


def test_io_figlet(cmk):
  r = cmk("io.figlet/hi")
  assert r.ok, r.stderr
