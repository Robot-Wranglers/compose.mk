"""compose.mk under minimal / busybox / non-FHS containers.

Two concerns:

1. REGRESSION (shebang fix): compose.mk's shebang is `#!/usr/bin/env bash` (NOT
   `env -S bash`).  busybox `env` (alpine) has no `-S` flag, so the old shebang made
   `compose.mk` un-executable in alpine UNLESS GNU coreutils was installed.  The fix means
   alpine + make + bash (NO coreutils) is enough to run/dispatch.  See test_*_without_coreutils.

2. DIAGNOSTICS (investigative): compose.mk's real exec-time deps are bash + make + awk + sed.
   A bash preflight in the polyglot header turns a raw `make: command not found` (or, on
   non-FHS nixos, `awk/sed: command not found`) into a clear "compose.mk needs ... install
   them" message.  These tests pin where each minimal image fails and that the message helps.

All tests here run real containers, so they are `needs_docker` (auto-skipped without a
daemon) and pull small public images (alpine; the nixos case pulls the larger `nixos/nix`).
"""

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"


def _run_in(image: str, tmp_path: Path, sh: str, timeout: int = 400):
  """Copy compose.mk into tmp_path, mount it at /w, run `sh -c <sh>` in <image>."""
  shutil.copy(COMPOSE_MK, tmp_path / "compose.mk")
  (tmp_path / "compose.mk").chmod(0o755)
  return subprocess.run(
    [
      "docker",
      "run",
      "--rm",
      "-e",
      "NO_COLOR=1",
      "-v",
      f"{tmp_path}:/w",
      "-w",
      "/w",
      image,
      "sh",
      "-c",
      sh,
    ],
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )


# --- 1. REGRESSION: the shebang fix (busybox env, no coreutils) ----------------


def test_busybox_runs_without_coreutils(tmp_path):
  # alpine = busybox `env` (no `-S`).  With ONLY make + bash (no coreutils), compose.mk must
  # run -- proving the `#!/usr/bin/env bash` shebang no longer needs GNU env.
  r = _run_in(
    "alpine:3.20",
    tmp_path,
    "apk add --no-cache make bash >/dev/null 2>&1 && ./compose.mk flux.ok",
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "succeeding as requested" in out
  assert "unrecognized option" not in out  # the old busybox `env -S` failure


def test_busybox_dispatch_without_coreutils(tmp_path):
  # The real-world scenario: dispatch a target INTO an alpine tool-container that has make +
  # bash but NO coreutils.  Mirrors the user's `tf`-container case; must work post-fix.
  shutil.copy(COMPOSE_MK, tmp_path / "compose.mk")
  (tmp_path / "compose.mk").chmod(0o755)
  (tmp_path / "Dockerfile.bb").write_text(
    "FROM alpine:3.20\nRUN apk add --no-cache make bash\n"  # deliberately NO coreutils
  )
  (tmp_path / "compose.yml").write_text(
    "services:\n"
    "  bbsvc:\n"
    "    build: {context: ., dockerfile: Dockerfile.bb}\n"
    "    working_dir: /workspace\n"
    "    volumes: ['.:/workspace']\n"
  )
  (tmp_path / "Makefile").write_text(
    "include compose.mk\n"
    "$(call compose.import, file=compose.yml)\n"
    ".incontainer:; @echo BUSYBOX-DISPATCH-OK host=$$(uname -n)\n"
  )
  r = subprocess.run(
    ["make", "-f", "Makefile", "bbsvc.dispatch/.incontainer"],
    cwd=tmp_path,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=600,
    env={"PATH": __import__("os").environ["PATH"], "NO_COLOR": "1"},
  )
  out = r.stdout + r.stderr
  assert "BUSYBOX-DISPATCH-OK" in out, out
  assert "unrecognized option" not in out


# --- 2. DIAGNOSTICS: missing-dep error messages --------------------------------
# (image, apk-packages-to-add, tools that should be reported missing)
_MISSING_CASES = [
  pytest.param("alpine:3.20", "bash", ["make"], id="alpine-no-make"),
  pytest.param("alpine:3.20", "bash make", [], id="alpine-complete"),
  # nixos/nix: HAS /usr/bin/env (GNU, via nix-store) + bash, but no make/awk/sed on PATH --
  # a non-FHS image where ALL THREE are reported.  Heavy pull; deselect with `-k 'not nixos'`.
  pytest.param(
    "nixos/nix", None, ["make", "awk", "sed"], id="nixos-no-toolchain"
  ),
]


@pytest.mark.parametrize("image,pkgs,missing", _MISSING_CASES)
def test_missing_dep_diagnostics(tmp_path, image, pkgs, missing):
  setup = f"apk add --no-cache {pkgs} >/dev/null 2>&1 && " if pkgs else ""
  r = _run_in(image, tmp_path, setup + "./compose.mk flux.ok")
  out = r.stdout + r.stderr
  if not missing:
    assert r.returncode == 0, out
    assert "succeeding as requested" in out
    return
  # the friendly preflight (compose.mk header) names compose.mk, the missing tool(s),
  # and how to install them -- instead of a bare `<tool>: command not found`.
  assert "compose.mk needs bash + make + awk + sed" in out, out
  for tool in missing:
    assert tool in out, (tool, out)
  assert "apk add make gawk sed" in out  # the install hint


def test_missing_bash_names_the_interpreter(tmp_path):
  # Pre-bash failure: with no bash, the shebang `env bash` can't even start, so the preflight
  # (itself bash) can't run.  Document that the error at least NAMES bash (busybox `env`).
  r = _run_in("alpine:3.20", tmp_path, "./compose.mk flux.ok")
  out = r.stdout + r.stderr
  assert r.returncode != 0
  assert (
    "bash" in out
  )  # e.g. "env: can't execute 'bash': No such file or directory"
