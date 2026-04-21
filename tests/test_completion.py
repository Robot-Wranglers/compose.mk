"""Bash-completion suite: the `cmk cli` verbs + the `.awk.completion.scan` enumerator.

Covers the fast, define-aware target scanner (the single source of truth shared with the repl's
local-target banner) and the emitted bash completion script, reached through the NESTED
subcommand path `cmk cli {complete,init,targets}`.  Pure target I/O, no docker:

  (a) `cmk cli targets` lists PUBLIC target base-names, define/endef-aware (no false positives
      from embedded Dockerfiles/awk), excluding private (`.`/`_`) + pattern (`%`) names;
  (b) the scan is a SUBSET of the independent `_targets.public_targets` reference parse, with the
      only difference being the `_`-prefixed names that completion deliberately hides;
  (c) `cmk cli complete` emits a valid, self-contained bash script (parses under `bash -n`) that
      defines `_cmk_complete` + registers it, with stdout carrying ONLY the script (clean `eval`);
  (d) a real shebang `.cmk` self-completes (its own targets are scanned live, via inheritance);
  (e) `cmk cli init` installs the script into the user's bash-completion dir (idempotent file).
"""

import os
import subprocess
from pathlib import Path

import pytest

from _targets import public_targets

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "logging.cmk"


def _run(*args, **env):
  return subprocess.run(
    [str(COMPOSE), *args],
    cwd=str(REPO),
    capture_output=True,
    text=True,
    stdin=subprocess.DEVNULL,
    timeout=90,
    env={"NO_COLOR": "1", "PATH": os.environ["PATH"], **env},
  )


def _scan(path=None):
  """Public base-names from `cmk cli targets [file]` (default file: CMK_SRC)."""
  r = _run("cmk", "cli", "targets", *([str(path)] if path else []))
  assert r.returncode == 0, r.stderr
  return set(r.stdout.split())


def _query(buf, **env):
  """QUERY mode: `CMK_COMPLETE_QUERY=1 ... cmk cli complete` with `buf` on stdin -> matches.

  This is what the repl's Go Tab handler calls (it pipes the input buffer through).
  """
  r = subprocess.run(
    [str(COMPOSE), "cmk", "cli", "complete"],
    cwd=str(REPO),
    input=buf,
    capture_output=True,
    text=True,
    timeout=90,
    env={
      "NO_COLOR": "1",
      "PATH": os.environ["PATH"],
      "CMK_COMPLETE_QUERY": "1",
      **env,
    },
  )
  assert r.returncode == 0, r.stderr
  return r.stdout.split()


def test_scanner_finds_known_targets():
  got = _scan()
  assert {"flux.ok", "io.bash", "cli.subcommands", "cmk", "cli.cmk.cli"} <= got


def test_scanner_excludes_private_and_patterns():
  got = _scan()
  assert not [t for t in got if t[:1] in ".-_"], "private/option names leaked"
  assert not [t for t in got if "%" in t], "pattern names leaked"


def test_scanner_is_subset_of_reference_parse():
  # The scanner must agree with the trusted independent parse, except that it ALSO hides
  # `_`-prefixed names (the reference keeps them).  So: scan is a subset, and everything the
  # reference has but the scan lacks is `_`-prefixed.
  got = _scan()
  ref = public_targets(COMPOSE)
  assert got <= ref, (
    f"scanner emitted names absent from reference: {sorted(got - ref)}"
  )
  only_ref = ref - got
  assert all(t.startswith("_") for t in only_ref), (
    f"non-private parity gap: {sorted(only_ref)}"
  )


def test_completion_bash_is_valid_and_registers():
  r = _run("cmk", "cli", "complete")
  assert r.returncode == 0, r.stderr
  assert "_cmk_complete()" in r.stdout
  assert "complete -F _cmk_complete" in r.stdout
  chk = subprocess.run(
    ["bash", "-n"], input=r.stdout, capture_output=True, text=True
  )
  assert chk.returncode == 0, chk.stderr


def test_completion_stdout_is_only_the_script():
  # `eval "$(... cmk cli complete)"` must see ONLY the script -- chatter belongs on stderr.
  r = _run("cmk", "cli", "complete")
  first = next(ln for ln in r.stdout.splitlines() if ln.strip())
  assert first.startswith("# compose.mk bash completion"), repr(first)


def test_query_prefix_matches_targets():
  # The repl Tab path: a prefix returns exactly the targets that start with it.
  got = set(_query("flux.o"))
  assert got == {"flux.ok", "flux.or"}, got
  assert _query("io.bash") == ["io.bash"]


def test_query_empty_buffer_returns_all():
  # Empty/whitespace buffer -> every candidate (like Tab on an empty prompt).
  assert set(_query("")) == _scan()
  assert set(_query("  ")) == _scan()


def test_query_completes_last_word_of_multiword_buffer():
  # Only the final token is completed; the head is irrelevant to the match set.
  assert set(_query("run flux.o")) == {"flux.ok", "flux.or"}


def test_query_includes_program_targets_via_interpreting():
  # A repl session sets __interpreting__ to the program; its OWN targets are offered too.
  own = _scan(DEMO)
  assert own, "demo has no public targets to assert against"
  target = sorted(own)[0]  # a stable own-target of the interpreted program
  # completing the program's own namespace prefix must surface that live-scanned target.
  got = _query(target.split(".")[0], __interpreting__=str(DEMO))
  assert target in got, (target, got)


def test_query_stdout_clean_no_supervisor_noise():
  # The Go side captures stdout; it must carry ONLY candidates (chatter stays on stderr).
  r = subprocess.run(
    [str(COMPOSE), "cmk", "cli", "complete"],
    cwd=str(REPO),
    input="flux.o",
    capture_output=True,
    text=True,
    timeout=90,
    env={
      "NO_COLOR": "1",
      "PATH": os.environ["PATH"],
      "CMK_COMPLETE_QUERY": "1",
    },
  )
  assert r.returncode == 0
  assert all(
    ln.strip() and " " not in ln.strip() for ln in r.stdout.splitlines()
  )


def test_init_installs_idempotent_completion_file(tmp_path):
  # `cmk cli init` writes ONE file into the XDG bash-completion dir (no shell-rc edits),
  # valid bash, and re-running overwrites in place (idempotent).
  for _ in range(2):
    r = _run("cmk", "cli", "init", XDG_DATA_HOME=str(tmp_path))
    assert r.returncode == 0, r.stderr
  dest = tmp_path / "bash-completion" / "completions" / "compose.mk"
  assert dest.is_file(), "init did not create the completion file"
  chk = subprocess.run(
    ["bash", "-n", str(dest)], capture_output=True, text=True
  )
  assert chk.returncode == 0, chk.stderr
  assert "complete -F _cmk_complete" in dest.read_text()


def test_completion_function_completes_stdlib_and_user_targets():
  # End-to-end: source the emitted script for a `.cmk`, drive the function, and confirm it offers
  # BOTH an inherited stdlib target and the program's OWN target (live-scanned from COMP_WORDS[0]).
  r = subprocess.run(
    [str(DEMO), "cmk", "cli", "complete"],
    cwd=str(REPO),
    capture_output=True,
    text=True,
    stdin=subprocess.DEVNULL,
    timeout=90,
    env={"NO_COLOR": "1", "PATH": os.environ["PATH"]},
  )
  assert r.returncode == 0, r.stderr
  script = r.stdout
  # Oracle = what the SCANNER emits for the demo (the function embeds the same scanner), so we
  # don't pick a name the scanner deliberately hides (e.g. `_`-prefixed `__main__`).
  own = _scan(DEMO)
  assert own, "demo has no public targets to assert against"
  sample = sorted(own)[0]
  drive = (
    f"{script}\n"
    f'COMP_WORDS=("{DEMO}" "flux.o"); COMP_CWORD=1; _cmk_complete; echo "STD:${{COMPREPLY[*]}}"\n'
    f'COMP_WORDS=("{DEMO}" "{sample}"); COMP_CWORD=1; _cmk_complete; echo "OWN:${{COMPREPLY[*]}}"\n'
  )
  out = subprocess.run(
    ["bash", "-c", drive], capture_output=True, text=True, cwd=str(REPO)
  ).stdout
  std = next(
    ln[4:] for ln in out.splitlines() if ln.startswith("STD:")
  ).split()
  own_out = next(
    ln[4:] for ln in out.splitlines() if ln.startswith("OWN:")
  ).split()
  assert "flux.ok" in std, f"inherited stdlib not offered: {std}"
  assert sample in own_out, (
    f"program's own target not offered: {sample} vs {own_out}"
  )
