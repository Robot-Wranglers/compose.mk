"""Pins for the beam.portal transport contract.

Envelope v2 (one JSON-RPC 2.0 object, flat to/reply_to extensions) rides two
transports unchanged: the socat unix-socket agent (docker-free) and the
portal (dockered).  Pinned: shape-folded cmk.push with per-actor seq order,
the ask round-trip (bare method, Response by id), the goals plane running
receiver-side, and mode-owned lifecycle leaving no container/relay/cells.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.experimental]

REPO = Path(__file__).resolve().parent.parent

_HANDLER = (
  "pin.upper:\n"
  "  '''ask handler: uppercase params.arg, answer by id'''\n"
  "  req=\"$${CMK_EVENT}\"\n"
  "  corr=`\"\"\"$$req\"\"\" | ${jq.run} -r .id`\n"
  "  who=`\"\"\"$$req\"\"\" | ${jq.run} -r .reply_to`\n"
  "  ans=`\"\"\"$$req\"\"\" | ${jq.run} -r '.params.arg | ascii_upcase'`\n"
  "  ${jq.run} -cn --arg c \"$$corr\" --arg r \"$$ans\" "
  "'{jsonrpc:\"2.0\",id:$$c,result:$$r}' | ${make} $$who.cast\n"
)

_SOCK_PROBE = (
  "#!/usr/bin/env -S ./compose.mk cmk run\n"
  "import log\n"
  "import jb, flux\n"
  "from agents import Agent, jqd, Askable, Jsonrpc\n"
  "class SockV2(bases=Askable,Jsonrpc,jqd)[|\n"
  "  '''probe: the socket transport speaking envelope v2, with ask'''\n"
  "|]\n"
  "export events__replies.mbox := .tmp.beamportalpin.replies.mbox\n"
  "replies <- Agent.new()\n"
  "SockV2 s2(| {v: (.name | ascii_upcase)} |)\n"
  + _HANDLER +
  "__main__:\n"
  "  s2.serve()\n"
  "  jb(name=carol) | s2.cast()\n"
  "  r=`printf '%s' \"ping\" | ${make} s2.ask/pin.upper`\n"
  "  s2.serve.stop()\n"
  "  echo \"REPLY=$$r\"\n"
  "  ${make} s2.mbox.dump\n"
)

_PORTAL_PROBE = (
  "#!/usr/bin/env -S ./compose.mk cmk run\n"
  "import log\n"
  "import jb, flux\n"
  "from agents import Agent\n"
  "from beam.portal import Portal, PortalActor, PortalAsk, PortalJqd\n"
  "portal0 <- Portal.new()\n"
  "export CMK_PRE := portal0.ensure\n"
  "export CMK_POST := portal0.reap\n"
  "PortalActor pa(portal=portal0)(| |)\n"
  "PortalJqd pb(portal=portal0)(| {v: (.name | ascii_upcase)} |)\n"
  "PortalAsk pc(portal=portal0)(| |)\n"
  "export events__replies.mbox := .tmp.beamportalpin.replies2.mbox\n"
  "replies <- Agent.new()\n"
  "pin.mark:\n"
  "  '''goals-plane proof: a side effect in the mounted workspace'''\n"
  "  touch .tmp.beamportalpin.mark\n"
  + _HANDLER +
  "__main__:\n"
  "  pa.serve(); \\\n"
  "  pb.serve(); \\\n"
  "  pc.serve()\n"
  "  jb(name=x1) | pa.cast()\n"
  "  jb(name=x2) | pa.cast()\n"
  "  jb(name=carol) | pb.cast()\n"
  "  \"\"\"pin.mark\"\"\" | pa.send()\n"
  "  r=`printf '%s' \"ping\" | ${make} pc.ask/pin.upper`\n"
  "  pa.serve.stop(); \\\n"
  "  pb.serve.stop(); \\\n"
  "  pc.serve.stop()\n"
  "  echo \"REPLY=$$r\"\n"
  "  echo PA-DUMP; ${make} pa.mbox.dump\n"
  "  echo PB-DUMP; ${make} pb.mbox.dump\n"
)


def _cleanup(*paths):
  for p in paths:
    Path(p).unlink(missing_ok=True)


@pytest.mark.skipif(shutil.which("socat") is None, reason="needs socat")
def test_envelope_v2_ask_on_socket_transport(cmk):
  probe = REPO / ".tmp.beamportalpin.sock.cmk"
  try:
    probe.write_text(_SOCK_PROBE)
    r = cmk("cmk", "run", str(probe.name), cwd=REPO,
            env={"CMK_SUPERVISOR": "1"}, timeout=300)
    out = r.stdout + r.stderr
    assert r.ok, f"socket probe failed\n{out[-2000:]}"
    assert "REPLY=PING" in out, f"ask round-trip failed\n{out[-2000:]}"
    assert '"v":"CAROL"' in out, f"shape fold missing\n{out[-2000:]}"
    assert '"seq":1' in out, f"seq missing\n{out[-2000:]}"
  finally:
    _cleanup(probe, REPO / ".tmp.beamportalpin.replies.mbox")


@pytest.mark.needs_docker
def test_envelope_v2_contract_on_portal_transport(cmk):
  probe = REPO / ".tmp.beamportalpin.portal.cmk"
  mark = REPO / ".tmp.beamportalpin.mark"
  try:
    probe.write_text(_PORTAL_PROBE)
    mark.unlink(missing_ok=True)
    r = cmk("cmk", "run", str(probe.name), cwd=REPO,
            env={"CMK_SUPERVISOR": "1"}, timeout=900)
    out = r.stdout + r.stderr
    assert r.ok, f"portal probe failed\n{out[-3000:]}"
    assert "REPLY=PING" in out, f"portal ask failed\n{out[-3000:]}"
    pa = out.partition("PA-DUMP")[2].partition("PB-DUMP")[0]
    assert '"seq":1' in pa and '"seq":2' in pa, f"pa serialization broken\n{pa}"
    assert pa.index('"name":"x1"') < pa.index('"name":"x2"'), (
      f"pa arrival order broken\n{pa}")
    pb = out.partition("PB-DUMP")[2]
    assert '"v":"CAROL"' in pb, f"portal shape fold missing\n{pb}"
    assert mark.exists(), "goals-plane target did not run portal-side"
    ps = subprocess.run(["docker", "ps", "-aq", "--filter", "name=cmk-portal-"],
                        capture_output=True, text=True, timeout=60)
    assert not ps.stdout.strip(), "portal container leaked"
    relay = subprocess.run(
      ["pgrep", "-f", "socat UNIX-LISTEN:.tmp.actor.portal0"],
      capture_output=True, text=True)
    assert relay.returncode != 0, "portal relay leaked"
    regs = list(REPO.glob(".tmp.cmk.scratch.*portal.reg.*"))
    assert not regs, f"registration cells leaked: {regs}"
  finally:
    _cleanup(probe, mark, REPO / ".tmp.beamportalpin.replies2.mbox")
