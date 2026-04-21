"""Black-box characterization of the tux.repl Go wrapper BINARY itself.

The wrapper is two things: a process/stream manager (spawn region children, pump their stdio, reap them) and
a config-JSON -> model layer (metadata -> UI).  The HEADLESS path (stdout not a tty) exposes the first half
as a pure pipe: feed piped stdin into the eval region, capture its output, print the exit sign-off as JSON.

These tests drive the built binary DIRECTLY with tiny fake `runner` scripts (a runner is invoked as
`<runner> <target>`), asserting on that JSON.  No compose.mk, no kernel, no docker-per-test, no pty -- so they
are fast + deterministic and PIN the wrapper's observable contract, which is the safety net for hardening and
shrinking the Go core.  (The macro-level wiring is covered separately in test_repl_signoff.py; the live render
half still needs the manual/pty path.)

The binary is cross-built on first use (docker) via `tux.repl.wrapper.bin`; hence `needs_docker`.  Later runs
reuse the per-host cache, so the tests themselves invoke no docker.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

pytestmark = [pytest.mark.external_plugin, pytest.mark.integration, pytest.mark.needs_docker]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
CMK_DIR = REPO / ".cmk"


@pytest.fixture(scope="session")
def wrapper_bin(tmp_path_factory):
  # build-if-needed + locate the wrapper via the tux.repl.wrapper.bin introspection target.
  d = tmp_path_factory.mktemp("wb")
  mk = d / "wb.mk"
  mk.write_text(f"include {COMPOSE}\n$(call include.plugins, tux.repl.cmk)\n")
  env = {
    **os.environ,
    "CMK_PLUGINS_DIR": str(CMK_DIR),
    "CMK_MODULES_DIR": str(d),
    "NO_COLOR": "1",
  }
  r = subprocess.run(
    ["make", "-f", str(mk), "tux.repl.wrapper.bin"],
    cwd=str(d),
    env=env,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=600,
  )
  path = (r.stdout or "").strip().splitlines()[-1] if r.stdout.strip() else ""
  if not path or not os.access(path, os.X_OK):
    pytest.skip(
      f"wrapper binary unavailable (build failed?):\n{r.stderr[-1500:]}"
    )
  return path


def _runner(tmp_path, name, body):
  f = tmp_path / name
  f.write_text("#!/bin/sh\n" + body)
  f.chmod(0o755)
  return str(f)


def _headless(
  wrapper_bin,
  runner,
  stdin_text,
  eval_target="e",
  extra_env=None,
  extra_regions=None,
):
  regions = {"runner": runner, "eval": eval_target}
  if extra_regions:
    regions.update(extra_regions)
  env = {
    **os.environ,
    "NO_COLOR": "1",
    "CMK_REPL_REGIONS": json.dumps(regions),
  }
  if extra_env:
    env.update(extra_env)
  r = subprocess.run(
    [wrapper_bin],
    input=stdin_text.encode(),
    capture_output=True,
    env=env,
    start_new_session=True,
    timeout=60,
  )
  return (
    r.returncode,
    r.stdout.decode("utf-8", "replace"),
    r.stderr.decode("utf-8", "replace"),
  )


# a runner that echoes each submitted line and marks a clean return (\x1e0)
ECHO = 'while IFS= read -r l; do printf "ran %s\\n" "$l"; printf "\\036%s\\n" 0; done\n'


def test_captures_output_and_rc(wrapper_bin, tmp_path):
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "echo.sh", ECHO), "flux.ok\n"
  )
  d = json.loads(
    out
  )  # stdout must be PURE JSON (eval output is captured, not streamed through)
  assert d["rc"] == 0, d
  assert "ran flux.ok" in d["screen"]["stdout_buffer"], d
  assert d["subprocs"]["eval"]["status"] == "exited", d
  assert d["screen"]["counts"]["in"] >= 1, d


def test_multiple_submissions_all_captured(wrapper_bin, tmp_path):
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "echo.sh", ECHO), "a\nb\nc\n"
  )
  sb = json.loads(out)["screen"]["stdout_buffer"]
  assert "ran a" in sb and "ran b" in sb and "ran c" in sb, sb


def test_marker_rc_propagates(wrapper_bin, tmp_path):
  body = 'while IFS= read -r l; do printf "boom %s\\n" "$l"; printf "\\036%s\\n" 2; done\n'
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "rc2.sh", body), "x\n"
  )
  d = json.loads(out)
  assert (
    d["rc"] == 2
    and d["screen"]["last_rc"] == 2
    and d["screen"]["have_rc"] is True
  ), d
  assert "\x1e" not in d["screen"]["stdout_buffer"], (
    "the marker must be stripped from the buffer"
  )


def test_ansi_is_stripped(wrapper_bin, tmp_path):
  body = 'while IFS= read -r l; do printf "\\033[92m%s ok\\033[0m\\n" "$l"; printf "\\036%s\\n" 0; done\n'
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "ansi.sh", body), "hi\n"
  )
  sb = json.loads(out)["screen"]["stdout_buffer"]
  assert "hi ok" in sb and "\x1b" not in sb, sb


def test_empty_stdin_is_clean(wrapper_bin, tmp_path):
  rc, out, err = _headless(wrapper_bin, _runner(tmp_path, "echo.sh", ECHO), "")
  d = json.loads(out)
  assert d["rc"] == 0, d
  assert isinstance(d["screen"]["stdout_buffer"], str), d


def test_no_eval_region_still_signs_off(wrapper_bin, tmp_path):
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "echo.sh", ECHO), "x\n", eval_target=""
  )
  d = json.loads(out)
  assert d["subprocs"]["eval"]["status"] == "absent", d
  assert "screen" in d, d


def test_file_sink_matches_stdout(wrapper_bin, tmp_path):
  sink = tmp_path / "signoff.json"
  rc, out, err = _headless(
    wrapper_bin,
    _runner(tmp_path, "echo.sh", ECHO),
    "flux.ok\n",
    extra_env={"CMK_REPL_SIGNOFF": str(sink)},
  )
  assert sink.exists(), err[-1000:]
  fromfile = json.loads(sink.read_text())
  assert (
    fromfile["screen"]["stdout_buffer"]
    == json.loads(out)["screen"]["stdout_buffer"]
  ), "sink != stdout"


def test_eval_process_failure_is_reported(wrapper_bin, tmp_path):
  rc, out, err = _headless(
    wrapper_bin, _runner(tmp_path, "fail.sh", "exit 3\n"), "x\n"
  )
  d = json.loads(out)
  assert d["subprocs"]["eval"]["status"] == "exited", d
  assert d["subprocs"]["eval"]["code"] == 3, d


def test_bad_regions_json_exits_2(wrapper_bin):
  env = {**os.environ, "NO_COLOR": "1", "CMK_REPL_REGIONS": "{not json"}
  r = subprocess.run(
    [wrapper_bin], input=b"", capture_output=True, env=env, timeout=30
  )
  assert r.returncode == 2, (r.returncode, r.stderr)
  assert b"CMK_REPL_REGIONS" in r.stderr, r.stderr


def test_help_flag(wrapper_bin):
  r = subprocess.run([wrapper_bin, "--help"], capture_output=True, timeout=30)
  assert r.returncode == 0 and b"tux-repl-wrapper" in r.stdout, r.stdout[:200]


# ── mapping layer (config-JSON -> model) via the headless read sample ────────────────────────────────
# A single runner serves BOTH regions by dispatching on its target arg: "rd" emits one metadata line then
# exits (a deterministic snapshot the wrapper feeds through applyMetaLine); anything else is the eval echo.
# So `screen.modeline` / `screen.minimaps` in the sign-off reflect the PARSED model -- the mapping layer is
# pinned with zero rendering.


def _dual_runner(tmp_path, read_line, name="dual.sh"):
  esc = read_line.replace("\\", "\\\\").replace('"', '\\"')
  body = (
    'if [ "$1" = "rd" ]; then\n'
    f'  printf "%s\\n" "{esc}"\n'
    "else\n"
    '  while IFS= read -r l; do printf "ran %s\\n" "$l"; printf "\\036%s\\n" 0; done\n'
    "fi\n"
  )
  return _runner(tmp_path, name, body)


def test_read_metadata_populates_modeline_and_minimaps(wrapper_bin, tmp_path):
  meta = '{"mode_lhs":"frame.demo","mode_rhs":"12:00:00","mm_config":{"middle":"tree"},"mm_tree":{"label":"vm","children":[]},"mm_top":"(Call Stack)"}'
  runner = _dual_runner(tmp_path, meta)
  rc, out, err = _headless(
    wrapper_bin, runner, "flux.ok\n", extra_regions={"read": "rd"}
  )
  d = json.loads(out)
  assert d["screen"]["modeline"]["lhs"] == "frame.demo", d["screen"][
    "modeline"
  ]
  assert d["screen"]["modeline"]["rhs"] == "12:00:00", d["screen"]["modeline"]
  mid = d["screen"]["minimaps"]["middle"]
  assert (
    mid["mode"] == "tree"
    and mid["tree_label"] == "vm"
    and mid["top"] == "(Call Stack)"
  ), mid
  assert d["screen"]["meta_mode"] is True, d["screen"]


def test_read_metadata_buffer_mode_routes_lines(wrapper_bin, tmp_path):
  # mm_config picks buffer(scroll) mode; a multi-line mm_buffer value splits into the scrollback tail.
  meta = '{"mm_config":{"top":"buffer"},"top_mm_buffer":"line-A\\nline-B","top_mm_top":"(Command Log)"}'
  runner = _dual_runner(tmp_path, meta)
  rc, out, err = _headless(
    wrapper_bin, runner, "x\n", extra_regions={"read": "rd"}
  )
  top = json.loads(out)["screen"]["minimaps"]["top"]
  assert top["mode"] == "buffer" and top["tail"] == ["line-A", "line-B"], top


def test_mode_segs_wide_keeps_all(wrapper_bin, tmp_path):
  # the DEFAULT modeline contract: feeder emits prioritized segments; Go elides to width + paints.  Wide -> all
  # kept (chain p=5, ip p=0, tail p=0).  mode_rhs is the feeder's OPTIONAL right text; "^D quit" is the
  # wrapper-owned STATIC quit hint, always appended after it.
  segs = '{"mode_segs":[{"t":"L5 c1 c2 ","s":"dim","p":5,"k":"R"},{"t":"frame.demo","s":"ip","p":0,"k":"L"},{"t":" K3 E{x} tail","s":"dim","p":0,"k":"R"}],"mode_rhs":"12:00"}'
  runner = _dual_runner(tmp_path, segs)
  rc, out, err = _headless(
    wrapper_bin,
    runner,
    "x\n",
    extra_regions={"read": "rd"},
    extra_env={"COLUMNS": "120"},
  )
  r = json.loads(out)["screen"]["modeline"]["rendered"]
  assert "frame.demo" in r and "c1 c2" in r and "K3 E{x} tail" in r, r
  assert "12:00" in r and r.rstrip().endswith("^D quit"), (
    r
  )  # optional mode_rhs, then the static quit hint last


def test_mode_segs_narrow_drops_lowprio_keeps_ip(wrapper_bin, tmp_path):
  # narrow -> the droppable chain (p=5) is elided, but the must-keep IP + tail (p=0) survive; the wrapper-owned
  # "^D quit" hint is always kept (mode_rhs, if any, is dropped first -- none here).
  segs = '{"mode_segs":[{"t":"chainchainchain ","s":"dim","p":5,"k":"R"},{"t":"frame.demo","s":"ip","p":0,"k":"L"},{"t":" K3","s":"dim","p":0,"k":"R"}]}'
  runner = _dual_runner(tmp_path, segs)
  rc, out, err = _headless(
    wrapper_bin,
    runner,
    "x\n",
    extra_regions={"read": "rd"},
    extra_env={"COLUMNS": "34"},
  )
  r = json.loads(out)["screen"]["modeline"]["rendered"]
  assert "frame.demo" in r and "^D quit" in r, (
    r
  )  # p=0 IP + the static quit hint survive
  assert "chainchainchain" not in r, r  # p=5 chain dropped to fit


def test_non_meta_read_line_is_ignored(wrapper_bin, tmp_path):
  # a plain (non-metadata) read line must NOT be treated as meta -> modeline stays empty, no crash.
  runner = _dual_runner(
    tmp_path, '{"cli":"x","lvl":1}'
  )  # legacy-shaped, no handler keys
  rc, out, err = _headless(
    wrapper_bin, runner, "x\n", extra_regions={"read": "rd"}
  )
  d = json.loads(out)
  assert d["screen"]["modeline"]["lhs"] is None, d["screen"]["modeline"]
  assert d["screen"].get("meta_mode") is False, d["screen"]


# ── minimal pty smoke: the INTERACTIVE path (bubbletea Update/submit/render) ──────────────────────────
# The headless tests above never touch the live TUI.  This one drives the real interactive wrapper under a
# pty -- type a target, submit, quit -- and reads the exit sign-off from CMK_REPL_SIGNOFF (a file, so no
# altscreen-framebuffer scraping).  It pins that a submission flows through Update -> eval -> the panel MODEL,
# guarding the interactive path when the renderers get refactored.  (Render PIXELS still need a human eyeball;
# this pins the model the renderer projects.)


@pytest.mark.skipif(sys.platform != "linux", reason="pty smoke is linux-only")
def test_pty_interactive_submit_reaches_model(wrapper_bin, tmp_path):
  import fcntl
  import pty
  import select
  import struct
  import termios
  import threading

  runner = _runner(tmp_path, "echo.sh", ECHO)
  sink = tmp_path / "signoff.json"
  master, slave = pty.openpty()
  fcntl.ioctl(
    slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0)
  )  # bubbletea needs a size to render
  env = {
    **os.environ,
    "NO_COLOR": "1",
    "CMK_REPL_REGIONS": json.dumps(
      {"runner": runner, "read": "", "eval": "e", "print": ""}
    ),
    "CMK_REPL_SIGNOFF": str(sink),
  }
  proc = subprocess.Popen(
    [wrapper_bin],
    stdin=slave,
    stdout=slave,
    stderr=slave,
    env=env,
    start_new_session=True,
    close_fds=True,
  )
  os.close(slave)
  stop = threading.Event()

  def _drain():  # keep the pty from filling (altscreen writes a lot) so the child never blocks
    while not stop.is_set():
      try:
        r, _, _ = select.select([master], [], [], 0.1)
        if r and not os.read(master, 65536):
          break
      except OSError:
        break

  th = threading.Thread(target=_drain, daemon=True)
  th.start()
  try:
    time.sleep(2.5)  # TUI comes up + eval child starts
    os.write(master, b"flux.ok\r")  # type + submit
    time.sleep(2.0)
    os.write(master, b"\x04")  # ctrl-d -> quit
    try:
      proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
      proc.kill()
      proc.wait()
  finally:
    stop.set()
    th.join(timeout=2)
    os.close(master)

  assert sink.exists(), "no sign-off file written on exit"
  d = json.loads(sink.read_text())
  assert "ran flux.ok" in d["screen"]["stdout_buffer"], d["screen"][
    "stdout_buffer"
  ]
  assert d["subprocs"]["eval"]["status"] in ("reaped", "exited"), d["subprocs"]
