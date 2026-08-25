"""The `help` target's enumeration and rendering contract.

`_help_gen` reads make's database, spanning its `# Files` and `# Implicit Rules`
sections, and drops a name carrying a dunder in any segment.

Piped, the listing stays flat and newline-delimited.  On a terminal it groups under a
bold namespace heading, italicises parametric names, and wraps on visible width.
"""

import os
import pty
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;:]*[a-zA-Z]")
_ENV = {"PATH": os.environ["PATH"], "CMK_DISABLE_HOOKS": "1"}

# One witness per quadrant of (hosted | seed) x (parametric | literal).
_WITNESSES = [
  "flux.retry/%",
  "hosted.selftest",
  "mk.help.target/%",
  "flux.ok",
]


def _lines(text):
  return [ln.rstrip() for ln in _ANSI.sub("", text).splitlines() if ln.strip()]


def _piped():
  r = subprocess.run(
    [str(COMPOSE), "help"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=300,
    env={**_ENV, "NO_COLOR": "1"},
  )
  assert r.returncode == 0, r.stderr
  return _lines(r.stdout)


def _on_tty(styled=False, **env):
  """Run `help` with stdout on a pty so the interactive branch is taken."""
  primary, secondary = pty.openpty()
  proc = subprocess.Popen(
    [str(COMPOSE), "help"],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    stdout=secondary,
    stderr=subprocess.DEVNULL,
    env={**_ENV, **env},
  )
  os.close(secondary)
  chunks = []
  try:
    while True:
      try:
        block = os.read(primary, 65536)
      except OSError:  # EIO once the far side closes
        break
      if not block:
        break
      chunks.append(block)
  finally:
    os.close(primary)
  assert proc.wait(timeout=300) == 0
  text = b"".join(chunks).decode(errors="replace").replace("\r\n", "\n")
  return text if styled else _lines(text)


def _grouped(lines):
  """Fold the rendered listing into a namespace-to-names mapping."""
  groups, current = {}, None
  for ln in lines:
    if ln.endswith(":") and not ln.startswith(" "):
      current = ln[:-1]
      groups.setdefault(current, [])
    elif current and ln.startswith("  "):
      groups[current].extend(ln.split())
  return groups


def test_piped_help_is_flat():
  """Piped output stays one bare target name per line, so callers can grep it."""
  lines = _piped()
  assert lines, "help produced nothing"
  assert not [ln for ln in lines if ln.startswith(" ")], (
    "indented lines leaked"
  )
  assert not [ln for ln in lines if ln.endswith(":")], "group headers leaked"


def test_help_spans_both_database_sections():
  listed = set(_piped())
  missing = [w for w in _WITNESSES if w not in listed]
  assert not missing, missing


def test_help_hides_dunders_in_any_segment():
  leaked = [ln for ln in _piped() if "__" in ln]
  assert not leaked, leaked


def test_tty_groups_under_namespace_headers():
  """Every name is filed under the heading naming its own root, and none is lost."""
  groups = _grouped(_on_tty())
  assert {"flux", "docker", "io"} <= set(groups), sorted(groups)
  for ns, names in groups.items():
    for name in names:
      assert name == ns or name.startswith((ns + ".", ns + "/")), (
        "%s filed under %s" % (name, ns)
      )
  assert sum(len(v) for v in groups.values()) == len(_piped())


def test_tty_wraps_on_visible_width():
  """Wrapping counts the name, not the styling, so no line overruns the terminal."""
  lines = _on_tty()
  members = [ln for ln in lines if ln.startswith("  ")]
  assert len(members) < len(_piped()), "grouping did not compact the list"
  assert max(len(ln) for ln in members) <= 200
  assert len([ln for ln in members if ln.strip().startswith("flux.")]) > 1


def test_tty_styles_headings_bold_and_parametrics_italic():
  raw = _on_tty(styled=True)
  assert "\x1b[1mflux:\x1b[0m" in raw, "namespace heading is not bold"
  assert "\x1b[3mflux.retry/%\x1b[0m" in raw, "parametric name is not italic"
  assert "\x1b[3mflux.ok\x1b[0m" not in raw, (
    "literal name should not be italic"
  )


def test_tty_honours_no_color():
  raw = _on_tty(styled=True, NO_COLOR="1")
  assert "flux:" in raw, "grouping lost under NO_COLOR"
  assert "\x1b[" not in raw, "styling leaked under NO_COLOR"
