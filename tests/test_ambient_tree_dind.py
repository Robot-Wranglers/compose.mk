"""Docker-in-docker pins for the dynamic ambient tree.

The docker-free chain pins live in test_machine_hierarchy_cmk (host
machines) and the depth-one crossing in test_ambients_cmk.  These two
tests pin what only real containers can: the chain composing at depth
two through boxes (with the multi-hop unwind), and unmediated sibling
messaging over a named channel.  The paired demos illustrate the same
behaviors; coverage lives here.

Both need an interpreter-capable dind image (make + bash + jq on the
stock busybox awk), built once per module and cached by docker layers.
Gated like the other container-heavy suites: CMK_TEST_DIND=1.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.dind,
  pytest.mark.covers_demo("machines-nested.cmk", "ambient-siblings.cmk"),
]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
IMAGE = "cmk-test-ambient-dind:latest"
DOCKERFILE = """FROM docker:dind
RUN apk add -q --update --no-cache coreutils bash make jq
"""


@pytest.fixture(scope="module")
def dind_image():
  build = subprocess.run(
    ["docker", "build", "-q", "-t", IMAGE, "-"],
    input=DOCKERFILE,
    capture_output=True,
    text=True,
    timeout=600,
  )
  if build.returncode != 0:
    pytest.skip(f"cannot build the dind image: {build.stderr[-300:]}")
  return IMAGE


def _run(name, src, *targets, timeout=600):
  f = REPO / name
  f.write_text(src)
  try:
    r = subprocess.run(
      [str(COMPOSE), "cmk", "run", str(f), *targets],
      cwd=str(REPO),
      stdin=subprocess.DEVNULL,
      capture_output=True,
      text=True,
      errors="replace",
      timeout=timeout,
    )
    return r.returncode, r.stdout + r.stderr
  finally:
    f.unlink(missing_ok=True)


def test_containerized_multihop_chain(dind_image):
  """Depth two through real boxes: the chain composes, and out unwinds it.

  Mirrors the host-machine chain tests, but every hop is a docker boundary:
  the hop bodies re-invoke this program via its own compiled artifact.
  """
  src = (
    "open cmk\n"
    f"container outer(img={dind_image} entrypoint=bash)(| |)\n"
    f"container inner(img={dind_image} entrypoint=bash)(| |)\n"
    "nest:\n"
    "  (| ${__cmk__} deep |) in outer\n"
    "deep:\n"
    '  (| echo "L2_AP=[$__ambient_parent__] L2_CUR=[$__ambient__]" |) in inner\n'
    "hop:\n"
    "  (| ${__cmk__} mid |) in outer\n"
    "mid:\n"
    "  (| ${__cmk__} leaf |) in inner\n"
    "leaf:\n"
    '  (| echo "OUT_AP=[$__ambient_parent__] OUT_CUR=[$__ambient__]" |) out\n'
  )
  rc, out = _run(".tmp.ambient.dind.chain.cmk", src, "nest", "hop")
  assert rc == 0, out[-2000:]
  assert "L2_AP=[outer] L2_CUR=[inner]" in out, out[-2000:]
  assert "OUT_CUR=[outer]" in out, out[-2000:]
  assert "OUT_AP=[host.local]" in out, out[-2000:]
  assert "OUT_AP=[outer]" not in out, out[-2000:]


def test_sibling_channel_exchange(dind_image):
  """A emits into a named channel in her box; B hears it in his.

  The parent schedules but never touches the payload.  Pins the two
  demo accommodations too: the source-pinned stack name (the run-keyed
  default does not cross the boundary) and the unsupervised hops (a
  supervised boot purges the channel at its own exit).
  """
  src = (
    "open cmk\n"
    "import stream\n"
    f"container boxa(img={dind_image} entrypoint=bash)(| |)\n"
    f"container boxb(img={dind_image} entrypoint=bash)(| |)\n"
    "export events__mailbox := .tmp.events__mailbox.dindtest\n"
    "channel mailbox(match='key=type value=ping')(|\n"
    "  []\n"
    "|)\n"
    "send:\n"
    "  (| CMK_SUPERVISOR=0 ${__cmk__} hop.emit |) in boxa\n"
    "hop.emit:\n"
    '  mailbox.emit["""type=ping from=$${__ambient__}"""]\n'
    "recv:\n"
    "  (| CMK_SUPERVISOR=0 ${__cmk__} hop.recv |) in boxb\n"
    "hop.recv:\n"
    "  ${make} mailbox.match\n"
    "mailbox.match/ping:\n"
    "  stream.as.log[${stream.stdin}]\n"
  )
  try:
    rc, out = _run(
      ".tmp.ambient.dind.sibs.cmk", src, "mailbox.initialize", "send", "recv"
    )
  finally:
    (REPO / ".tmp.events__mailbox.dindtest").unlink(missing_ok=True)
  assert rc == 0, out[-2000:]
  assert out.count('"from":"boxa"') == 1, out[-2000:]
