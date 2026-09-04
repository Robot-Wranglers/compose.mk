"""Headless suite for the embedded TUI (docs: 'TUI Overview & Gallery').

The embedded TUI -- the ``compose.mk:tux`` container running tmux via tmuxp -- is
normally interactive and ends in ``tmux attach``, which needs a real terminal.
This suite drives it HEADLESSLY (the ``tui`` fixture: stdin closed + a time-box)
and asserts on the tmuxp *load* markers (and the absence of known failure
signatures) rather than on the exit code -- the final attach always fails without
a tty, so a nonzero exit is expected and not interesting.

Heavy + opt-in: building ``compose.mk:tux`` compiles tmux from source and pulls
lazydocker + tpm, so the whole suite is gated behind ``CMK_TEST_TUI=1`` (like the
network/nushell opt-ins) and excluded from default CI. Run with::

    CMK_TEST_TUI=1 python -m pytest tests/test_integration_tui.py -q

or ``make tui-test`` / the on-demand ``.github/workflows/tui-tests.yml``.
"""

import re

import pytest

pytestmark = [
  pytest.mark.integration,
  pytest.mark.needs_docker,
  pytest.mark.tui,
]

_ANSI = re.compile(r"\x1b\[[0-9;]*m")

# Failure signatures that must NOT appear in a healthy TUI load. Each guards a
# real bug this suite was written for:
#   - window_id / TmuxObject : the tmuxp pane key must be `shell_command` (not the
#     bogus `shell`), else fast-exiting panes race libtmux's new_window lookup.
#   - No such file / No rule / undefined variable : the loadf makefile must
#     `include` a path valid INSIDE the container (workspace-relative), not the
#     absolute host CMK_SRC -- else compose.import.generic is never defined.
#   - bad substitution : that include path must be shell-expandable in the heredoc.
_TUI_FAILURES = (
  "Could not find window_id",
  "TmuxObjectDoesNotExist",
  "No such file or directory",
  "No rule to make target",
  "undefined variable",
  "bad substitution",
  "Traceback (most recent call last)",
)


def _clean(text: str) -> str:
  return _ANSI.sub("", text)


def _assert_session_loaded(out: str) -> None:
  clean = _clean(out)
  tail = clean[-3000:]
  # tmuxp prints this once it has built the session + its panes.
  assert "Loaded workspace" in clean, f"tmuxp never loaded a session:\n{tail}"
  assert "panes]" in clean, f"no panes reported in the load summary:\n{tail}"
  for bad in _TUI_FAILURES:
    assert bad not in clean, f"TUI failure signature {bad!r} present:\n{tail}"


def test_loadf_opens_tui(tui):
  # `loadf <compose>` builds the tux stack and loads a tmuxp session with one
  # pane per service. Exercises the whole host->container path: profile
  # generation, the workspace-relative `include`, and per-service shell panes.
  r = tui("loadf", "demos/data/docker-compose.yml")
  _assert_session_loaded(r.stdout)


def test_tux_open_loads_session(tui):
  # `tux.open/<t1>,<t2>` -- the generic TUI entrypoint -- opens the targets in
  # tmux panes. Same headless contract as loadf.
  r = tui("tux.open/flux.ok,flux.ok")
  _assert_session_loaded(r.stdout)


def test_tux_dispatch_runs_target_in_container(tui):
  # Non-TUI tux path: run a compose.mk target INSIDE the tux container. This one
  # completes (no tmux attach), so the target's success marker is reliable.
  r = tui("tux.dispatch/flux.ok")
  out = _clean(r.stdout)
  assert "flux.ok" in out, out[-2000:]
  for bad in _TUI_FAILURES:
    assert bad not in out, f"{bad!r} present:\n{out[-2000:]}"


def test_tux_dispatch_under_global_install(staged_global):
  # Same dispatch, but with compose.mk staged OUTSIDE the workspace (a global /
  # on-PATH install). Verifies the docker.cmk.mount + makefile_list.dind rewrite
  # make compose.mk resolvable inside the container when it isn't in /workspace.
  r = staged_global("tux.dispatch/flux.ok")
  assert r.returncode == 0, r.stderr
  assert "flux.ok" in (r.stdout + r.stderr)
