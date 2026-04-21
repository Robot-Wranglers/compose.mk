"""tux.repl headless sign-off: the pty-free e2e roundtrip.

When stdout is not a tty AND `CMK_REPL_STRUCTURED=1`, the `tux.repl` macro execs the Go wrapper HEADLESS
instead of the raw shell-batch stream: the wrapper feeds piped stdin into the eval region, captures the
output, and prints the exit SIGN-OFF as JSON to stdout -- with the captured panel text in
`screen.stdout_buffer`.  That makes an end-to-end assertion a plain pipe:

    echo flux.ok | CMK_REPL_STRUCTURED=1 ./prog | jq -r .screen.stdout_buffer | grep ...

no pty, no altscreen scraping.  These cover: (a) the roundtrip emits valid JSON carrying the target's
output + region endings; (b) the CMK_REPL_SIGNOFF file sink; and (c) the opt-in guard -- WITHOUT the flag,
the default batch path stays the raw shell stream (not JSON), so nothing here changes existing batch behavior.

The wrapper is cross-built on first use (docker), hence `needs_docker`; later runs hit the per-host cache.
"""

import json
import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.external_plugin, pytest.mark.integration, pytest.mark.needs_docker]

REPO = Path(__file__).resolve().parent.parent
DEMO = REPO / "demos" / "cmk" / "repl.cmk"


def _run(stdin_text, extra_env=None, timeout=180):
  env = {**os.environ, "NO_COLOR": "1"}
  if extra_env:
    env.update(extra_env)
  r = subprocess.run(
    [str(DEMO)],
    cwd=str(REPO),
    input=stdin_text.encode(),
    capture_output=True,
    start_new_session=True,
    env=env,
    timeout=timeout,
  )
  return (
    r.returncode,
    r.stdout.decode("utf-8", "replace"),
    r.stderr.decode("utf-8", "replace"),
  )


def test_structured_headless_roundtrip():
  # echo flux.ok | CMK_REPL_STRUCTURED=1 prog  ->  a JSON sign-off on stdout, target output captured.
  rc, out, err = _run("flux.ok\n", {"CMK_REPL_STRUCTURED": "1"})
  d = json.loads(
    out
  )  # stdout must be PURE JSON (eval output is captured into the buffer, not streamed)
  assert d["rc"] == 0, d
  assert d["subprocs"]["eval"]["status"] == "exited", d
  sb = d["screen"]["stdout_buffer"]
  assert "flux.ok" in sb and "succeeding as requested" in sb, (
    sb
  )  # the target actually ran, output captured
  assert (
    isinstance(d["screen"]["panel_tail"], list) and d["screen"]["panel_tail"]
  ), d
  assert d["screen"]["counts"]["in"] >= 1, d


def test_signoff_file_sink():
  # CMK_REPL_SIGNOFF=<path> ALSO writes the sign-off JSON to a file -- a capture channel independent of stdout.
  sink = REPO / "tests" / ".tmp.signoff.json"
  try:
    rc, out, err = _run(
      "flux.ok\n", {"CMK_REPL_STRUCTURED": "1", "CMK_REPL_SIGNOFF": str(sink)}
    )
    assert sink.exists(), f"sink not written\nstderr:\n{err[-1500:]}"
    d = json.loads(sink.read_text())
    assert "screen" in d and "stdout_buffer" in d["screen"], d
  finally:
    sink.unlink(missing_ok=True)


def test_default_batch_is_not_json():
  # OPT-IN GUARD: without CMK_REPL_STRUCTURED, the no-tty path stays the raw shell-batch stream (unchanged
  # contract) -- stdout is target output, NOT a JSON sign-off.
  rc, out, err = _run("flux.ok\n")
  with pytest.raises(json.JSONDecodeError):
    json.loads(out)
