"""Dialect-compatibility pins for the CMK compiler.

The compiler must behave identically under gawk, mawk, busybox awk, and the
one-true-awk: debian/ubuntu default to mawk, alpine to busybox, macOS to
BWK, so requiring gawk would contradict the no-dependencies posture.  Three
pins, cheapest first:

  * an authoring-time lint over every awk block for the construct classes
    that broke a dialect during the original port (each rule cites its
    victim), catching drift before any dialect ever executes;
  * a byte-oracle proving a UTF-8 locale cannot change compiler output
    (the pipeline pins LC_ALL=C internally; macOS BWK dies without it,
    and any pytest-launched subprocess inherits LC_CTYPE from CPython);
  * the matrix: ONE heavy gated test that builds a container holding all
    four dialects and reruns the whole compiler suite per dialect,
    asserting each dialect fails exactly the same tests as the
    in-container gawk baseline (so known breakages and environmental
    failures cancel out instead of needing a hardcoded list).
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler

REPO = Path(__file__).resolve().parent.parent
COMPOSE_MK = REPO / "compose.mk"
THIS_FILE = Path(__file__).name

# each forbidden construct cites the dialect it broke during the port.
AWKISM_RULES = [
  (r"\bgensub\s*\(", "gensub is gawk-only (mawk/busybox/bwk lack it)"),
  (r"\bmatch\s*\([^()]*\([^()]*\)[^()]*,[^()]*,", "3-arg match is gawk-only"),
  (r"\bPROCINFO\b", "PROCINFO is gawk-only"),
  (r"\basorti?\s*\(", "asort/asorti are gawk-only"),
  (r"RS='\\\\0'|RS=\"\\\\0\"", "NUL RS reads as paragraph mode in busybox"),
  (
    r"\[[^]\n]*\\\][^]\n]*\]",
    "escaped close-bracket in a class breaks busybox (put a literal ] first)",
  ),
  (
    r"gsub\([^)]*,\s*\"[^\"]*\\\\\\\\[&\"]",
    "backslash escapes in gsub replacements diverge per dialect (use split/join splices)",
  ),
  (
    r"=\s*close\s*\(",
    "close() as a status is not portable (bwk returns 0, busybox the raw wait status); deliver the status in-band",
  ),
]
# in-class unescaped slash inside a /regex/ literal terminates the literal in busybox.
CLASS_SLASH = re.compile(r"/(?:[^/\\\n]|\\.)*/")
IN_CLASS_SLASH = re.compile(r"\[[^]\n]*(?<!\\)/[^]\n]*\]")


def _awk_blocks():
  src = COMPOSE_MK.read_text(errors="replace")
  return dict(
    re.findall(
      r"^define ([._A-Za-z0-9]*(?:awk|awklang)[._A-Za-z0-9]*)\n(.*?)^endef",
      src,
      re.M | re.S,
    )
  )


def test_awk_blocks_stay_dialect_agnostic():
  blocks = _awk_blocks()
  assert len(blocks) > 30, "block extraction broke; update the pattern"
  problems = []
  for name, body in blocks.items():
    if ".jq." in name:
      continue
    for pat, why in AWKISM_RULES:
      for m in re.finditer(pat, body):
        problems.append(f"{name}: {why}: {m.group(0)[:50]!r}")
    for lit in CLASS_SLASH.finditer(body):
      if IN_CLASS_SLASH.search(lit.group(0)[1:-1]):
        problems.append(
          f"{name}: unescaped / inside a class in a regex literal: {lit.group(0)[:50]!r}"
        )
  assert not problems, "\n".join(problems)


def _hosted_body(tmp_path):
  out = tmp_path / "hosted.body"
  prog = (
    "/^define __hosted__$/{f=1;d=0;next} f{ line=$0; "
    'sub(/^  /,"",line); '
    "if(line ~ /^endef[ \\t]*$/){ if(d==0){f=0;next} d--; print line; next } "
    "if(line ~ /^define /)d++; print line }"
  )
  r = subprocess.run(
    ["awk", prog, str(COMPOSE_MK)], capture_output=True, text=True, timeout=60
  )
  assert r.returncode == 0 and len(r.stdout) > 10000
  out.write_text(r.stdout)
  return out


def _transpile(body, extra_env=None):
  env = {**os.environ, "NO_COLOR": "1", "TERM": "dumb", "CMK_SUPERVISOR": "0"}
  env.update(extra_env or {})
  r = subprocess.run(
    ["make", "-f", str(COMPOSE_MK), "lang.transpile"],
    stdin=body.open("rb"),
    capture_output=True,
    cwd=str(REPO),
    env=env,
    timeout=300,
  )
  lines = [ln for ln in r.stdout.splitlines() if b".tmp." not in ln]
  return r.returncode, b"\n".join(lines)


def test_utf8_locale_cannot_change_compiler_output(tmp_path):
  body = _hosted_body(tmp_path)
  rc0, base = _transpile(body)
  assert rc0 == 0 and len(base) > 10000, "baseline transpile failed"
  rc1, got = _transpile(
    body, extra_env={"LC_CTYPE": "C.UTF-8", "LANG": "en_US.UTF-8"}
  )
  assert rc1 == 0, "transpile failed under a UTF-8 locale"
  assert got == base, (
    "a UTF-8 locale changed compiler output (the LC pin is broken)"
  )


# ---- the matrix -------------------------------------------------------------
# One expensive test IS the matrix: all four dialects in one container, the
# whole compiler suite per dialect, failure sets compared to the in-container
# gawk baseline.  Roughly 30 minutes; gated like the other heavies.

MATRIX_DIALECTS = ("gawk", "mawk", "busybox", "bwk")
MATRIX_IMAGE = "cmk-test-awk-matrix:latest"
MATRIX_DOCKERFILE = """FROM debian:bookworm-slim
RUN apt-get update -qq >/dev/null 2>&1; \
    apt-get install -y -qq make bash jq git gawk mawk busybox original-awk \
      python3-pip python3-venv >/dev/null 2>&1
COPY requirements-test.txt /tmp/
RUN python3 -m venv /venv && /venv/bin/pip install -q -r /tmp/requirements-test.txt
"""
MATRIX_TARGETS = {
  "gawk": "/usr/bin/gawk",
  "mawk": "/usr/bin/mawk",
  "busybox": None,
  "bwk": "/usr/bin/original-awk",
}


def _repo_mounts():
  mounts = ["-v", f"{REPO}:{REPO}"]
  gitfile = REPO / ".git"
  if gitfile.is_file():
    gitdir = gitfile.read_text().split("gitdir:", 1)[1].strip()
    main = str(Path(gitdir).parent.parent)
    mounts += ["-v", f"{main}:{main}:ro"]
  return mounts


@pytest.mark.awk_matrix
@pytest.mark.needs_docker
def test_compiler_suite_is_dialect_invariant(tmp_path):
  build = subprocess.run(
    [
      "docker",
      "build",
      "-q",
      "-t",
      MATRIX_IMAGE,
      "-f",
      "-",
      str(REPO / "tests"),
    ],
    input=MATRIX_DOCKERFILE,
    capture_output=True,
    text=True,
  )
  if build.returncode != 0:
    pytest.skip(f"cannot build the matrix image: {build.stderr[-300:]}")
  shims = tmp_path / "shims"
  for d in MATRIX_DIALECTS:
    sd = shims / d
    sd.mkdir(parents=True)
    body = (
      'exec busybox awk "$@"\n'
      if d == "busybox"
      else f'exec "{MATRIX_TARGETS[d]}" "$@"\n'
    )
    (sd / "awk").write_text("#!/bin/sh\n" + body)
    (sd / "awk").chmod(0o755)
  failed = {}
  for d in MATRIX_DIALECTS:
    r = subprocess.run(
      [
        "docker",
        "run",
        "--rm",
        *_repo_mounts(),
        "-v",
        f"{shims}:{shims}:ro",
        "-w",
        f"{REPO}/tests",
        "-e",
        "NO_COLOR=1",
        "-e",
        "TERM=dumb",
        "-e",
        f"PATH={shims}/{d}:/venv/bin:/usr/local/bin:/usr/bin:/bin",
        MATRIX_IMAGE,
        "/venv/bin/pytest",
        "-q",
        "-m",
        "compiler",
        f"--ignore={THIS_FILE}",
        "-p",
        "no:cacheprovider",
        ".",
      ],
      capture_output=True,
      text=True,
      timeout=3600,
    )
    ids = sorted(
      ln.split()[1] for ln in r.stdout.splitlines() if ln.startswith("FAILED ")
    )
    ran = "passed" in (r.stdout.splitlines()[-1] if r.stdout else "")
    assert ran or ids, (
      f"{d}: suite did not run:\n{r.stdout[-800:]}\n{r.stderr[-400:]}"
    )
    failed[d] = ids
  base = failed["gawk"]
  drift = {d: ids for d, ids in failed.items() if ids != base}
  assert not drift, (
    f"dialect drift vs in-container gawk baseline {base}:\n"
    + "\n".join(f"{d}: {ids}" for d, ids in drift.items())
  )
