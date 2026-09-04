"""The bound file-banana model: `dockerfs NAME(bind=IMG path=P mode=M)(| body |)`.

A `dockerfs` is a file bound to an image at declaration.  Its body is captured
verbatim into `NAME.shape`, and `bind=` eagerly registers it on the image's
`__files__` list with the given `path=`/`mode=`.  A `Dockerfile` whose `__files__`
is non-empty folds them in at build time: each file is materialized into a
private context and a `COPY`/`RUN chmod` pair is spliced right after the first
`FROM`, so the Dockerfile body itself carries no scripts and no copy lines.

Compile-level lowering and registration are docker-free `unit`; the build+run
round-trip is `needs_docker`.  Companion to `demos/cmk/machine-qemu-exfile.cmk`.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.dockerfile, pytest.mark.covers_demo("machine-qemu-exfile.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
DEMO = REPO / "demos" / "cmk" / "machine-qemu-exfile.cmk"

HDR = "from cmk import dockerfs, Dockerfile\n"
# the image body has a line after its base so injection ordering is observable
IMG = "Dockerfile img(|\n  FROM alpine:3.21\n  RUN true\n|)\n"


def _transpile(src, timeout=120):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r.stdout


def _run(tmp_path, src, *goals, timeout=300):
  f = tmp_path / "df.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *goals],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


def _docker(*args, timeout=120):
  return subprocess.run(
    ["docker", *args], capture_output=True, text=True, errors="replace", timeout=timeout
  )


# --- A. callform and capture (unit) --------------------------------------------


@pytest.mark.unit
@pytest.mark.compiler
def test_callform_lowers_to_ctor_with_kwargs():
  # the declaration lowers to a dockerfs ctor call plus a define holding the body
  low = _transpile(
    HDR + "dockerfs g1(bind=img path=/etc/g1 mode=+x)(|\n  hello\n|)\n"
  )
  assert "define g1" in low, low
  assert "$(call dockerfs, def=g1 bind=img path=/etc/g1 mode=+x)" in low, low


@pytest.mark.unit
@pytest.mark.banana
def test_body_captured_verbatim():
  # shell specials and backslash escapes must survive capture unmangled
  body = '  home=$HOME\n  x=$(date)\n  y=${z#p}\n  printf \'a\\tb\\n\'\n'
  low = _transpile(HDR + "dockerfs g1(bind=img path=/x mode=+x)(|\n" + body + "|)\n")
  for frag in ("home=$HOME", "x=$(date)", "y=${z#p}", "printf 'a\\tb\\n'"):
    assert frag in low, (frag, low)


# --- B. registration (unit) ----------------------------------------------------


@pytest.mark.unit
def test_bind_registers_on_image(tmp_path):
  src = (
    HDR + IMG
    + "dockerfs g1(bind=img path=/etc/g1 mode=+x)(|\n  hello\n|)\n"
    + "show:\n\t@echo \"FILES=[${img.__files__}]\"\n"
  )
  _, out = _run(tmp_path, src, "show")
  assert "FILES=[g1]" in out, out


@pytest.mark.unit
def test_path_and_mode_stamped(tmp_path):
  src = (
    HDR + IMG
    + "dockerfs g1(bind=img path=/usr/local/bin/g1 mode=0755)(|\n  hi\n|)\n"
    + "show:\n\t@echo \"P=[${g1.__path__}] M=[${g1.__mode__}]\"\n"
  )
  _, out = _run(tmp_path, src, "show")
  assert "P=[/usr/local/bin/g1] M=[0755]" in out, out


@pytest.mark.unit
def test_two_files_register_in_order(tmp_path):
  src = (
    HDR + IMG
    + "dockerfs a(bind=img path=/a mode=+x)(|\n  a\n|)\n"
    + "dockerfs b(bind=img path=/b mode=+x)(|\n  b\n|)\n"
    + "show:\n\t@echo \"FILES=[${img.__files__}]\"\n"
  )
  _, out = _run(tmp_path, src, "show")
  assert "FILES=[a b]" in out, out


@pytest.mark.unit
def test_no_cross_leak_between_images(tmp_path):
  src = (
    HDR
    + "Dockerfile one(|\n  FROM alpine:3.21\n|)\n"
    + "Dockerfile two(|\n  FROM alpine:3.21\n|)\n"
    + "dockerfs a(bind=one path=/a mode=+x)(|\n  a\n|)\n"
    + "dockerfs b(bind=two path=/b mode=+x)(|\n  b\n|)\n"
    + "show:\n\t@echo \"ONE=[${one.__files__}] TWO=[${two.__files__}]\"\n"
  )
  _, out = _run(tmp_path, src, "show")
  assert "ONE=[a] TWO=[b]" in out, out


@pytest.mark.unit
def test_registration_is_eager_before_image_declared(tmp_path):
  # declaring the file before its image still registers it (eager, order-independent)
  src = (
    HDR
    + "dockerfs a(bind=img path=/a mode=+x)(|\n  a\n|)\n"
    + IMG
    + "show:\n\t@echo \"FILES=[${img.__files__}]\"\n"
  )
  _, out = _run(tmp_path, src, "show")
  assert "FILES=[a]" in out, out


# --- C. build injection, render only (unit, no docker) -------------------------


def _render(tmp_path, extra):
  src = HDR + IMG + extra + "render:\n\t@${make} img.render\n"
  r, _ = _run(tmp_path, src, "render")
  return r.stdout


@pytest.mark.unit
@pytest.mark.compiler
def test_render_injects_copy_and_chmod_after_from(tmp_path):
  # injected copy lands after the base line and before the body's own build step
  out = _render(
    tmp_path,
    "dockerfs g1(bind=img path=/etc/g1 mode=+x)(|\n  hello\n|)\n",
  )
  assert "COPY g1 /etc/g1" in out, out
  assert "RUN chmod +x /etc/g1" in out, out
  assert out.index("FROM alpine") < out.index("COPY g1") < out.index("RUN true"), out


@pytest.mark.unit
@pytest.mark.compiler
def test_render_injection_order_matches_files(tmp_path):
  out = _render(
    tmp_path,
    "dockerfs a(bind=img path=/a mode=+x)(|\n  a\n|)\n"
    "dockerfs b(bind=img path=/b mode=0644)(|\n  b\n|)\n",
  )
  assert out.index("COPY a /a") < out.index("COPY b /b"), out
  assert "RUN chmod 0644 /b" in out, out


@pytest.mark.unit
@pytest.mark.compiler
def test_render_no_files_is_untouched(tmp_path):
  # an image with no bound files renders its recipe unchanged (backward compat)
  src = HDR + IMG + "render:\n\t@${make} img.render\n"
  r, _ = _run(tmp_path, src, "render")
  out = r.stdout
  assert "FROM alpine:3.21" in out, out
  assert "COPY " not in out, out
  assert "chmod" not in out, out


# --- E. end-to-end in the image (needs docker) ---------------------------------


@pytest.mark.docker
@pytest.mark.needs_docker
def test_build_lands_files_with_mode(tmp_path):
  # the bound file lands executable at its path and runs inside the image
  tag = "compose.mk:cmktest_dockerfs"
  _docker("rmi", "-f", tag)
  src = (
    "from cmk import dockerfs, Dockerfile\n"
    "Dockerfile cmktest_dockerfs(|\n  FROM alpine:3.21\n|)\n"
    "dockerfs script(bind=cmktest_dockerfs path=/usr/local/bin/script mode=+x)(|\n"
    "  #!/bin/sh\n  echo bound-file-ran home=$HOME\n|)\n"
    "__main__: cmktest_dockerfs.build\n"
  )
  try:
    p, out = _run(tmp_path, src)
    assert p.returncode == 0, out
    ls = _docker("run", "--rm", "--entrypoint", "ls", tag, "-l", "/usr/local/bin/script")
    assert "-rwx" in ls.stdout, ls.stdout + ls.stderr
    run = _docker("run", "--rm", "--entrypoint", "/usr/local/bin/script", tag)
    assert "bound-file-ran" in run.stdout, run.stdout + run.stderr
  finally:
    _docker("rmi", "-f", tag)


@pytest.mark.docker
@pytest.mark.needs_docker
def test_demo_boots_guest(tmp_path):
  # the companion demo builds via the folded build and boots a guest
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(DEMO)],
    cwd=str(REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=600,
  )
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "hello from inside a qemu guest" in out, out
  assert "guest kernel" in out, out
