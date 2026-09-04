#!/usr/bin/env python3
# Imperative build glue layered on top of pyproject.toml (which carries the static
# metadata + `script-files`).  Its ONE job: bundle the stdlib CMK plugins (the
# repo-root `.cmk/` submodule) INTO this package as real, in-tree files, so a
# global install ships them on disk -- the `cmk` wrapper points CMK_PLUGINS_DIR at
# them when there is no project-local `./.cmk` (see ./cmk).
#
# We COPY (not symlink) on purpose:
#   * a `../../.cmk` symlink escapes the sdist root and would dangle once unpacked;
#   * `.cmk` is a git SUBMODULE, so copying at build time also lets an already-built
#     sdist stay self-contained when the submodule isn't present at install time.
#
# Three install paths, one handler (`_materialize`):
#   * git+URL  -> pip full-clones + inits submodules; SRC present -> copy.
#   * sdist build (`python -m build`) -> SRC present -> copy; MANIFEST.in ships _plugins/.
#   * sdist install -> SRC absent but _plugins/ already in the tarball -> keep as-is.
import os
import sys
import glob
import shutil
import subprocess

from setuptools import setup

HERE = os.path.dirname(os.path.abspath(__file__))


def _cmk_version():
    # The semver baked into the repo-root compose.mk (`CMK_VERSION := <x>`).  Only accept a
    # real release number -- the `0.0.0-dev` between-releases placeholder isn't PEP 440-valid,
    # so we ignore it and fall through to `0.0.0`.
    import re
    try:
        with open(os.path.join(HERE, "..", "..", "compose.mk"), encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"\s*CMK_VERSION\s*:?=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$", line)
                if m:
                    return m.group(1)
    except Exception:
        pass
    return ""


def _version():
    # `pyproject.toml` declares the version `dynamic`; resolve it here so the package
    # respects VERSION.  Order: explicit `VERSION` env (used by `gitops.release`) ->
    # the current git tag (`pip install ...@v1.2.3` checks the tag out) -> the baked
    # `CMK_VERSION` (a bare source build) -> `0.0.0`.
    v = (os.environ.get("VERSION") or "").strip()
    if v:
        return v.lstrip("v")
    try:
        out = subprocess.check_output(
            ["git", "describe", "--tags", "--abbrev=0"],
            cwd=HERE, stderr=subprocess.DEVNULL,
        )
        tag = out.decode().strip()
        if tag:
            return tag.lstrip("v")
    except Exception:
        pass
    return _cmk_version() or "0.0.0"
SRC = os.path.normpath(os.path.join(HERE, "..", "..", ".cmk"))  # repo-root submodule
DST = os.path.join(HERE, "_plugins")                            # materialized, gitignored


def _plugin_sources(d):
    # Shippable stdlib plugins: *.mk / *.cmk, EXCLUDING the submodule's own nested
    # `compose.mk` copy and any `.tmp.*` / scratch build cruft.
    out = []
    for pat in ("*.mk", "*.cmk"):
        for f in glob.glob(os.path.join(d, pat)):
            b = os.path.basename(f)
            if b == "compose.mk" or b.startswith(".tmp."):
                continue
            out.append(f)
    return sorted(out)


def _materialize():
    srcs = _plugin_sources(SRC) if os.path.isdir(SRC) else []
    if srcs:
        os.makedirs(DST, exist_ok=True)
        for f in srcs:
            shutil.copy2(f, os.path.join(DST, os.path.basename(f)))
        return
    # SRC absent (e.g. installing from an already-built sdist): keep whatever the
    # sdist bundled.  Only if BOTH are empty do we warn -- the binaries still
    # install fine, just without bundled plugins (`cmk repl` / polyglot then need a
    # project-local ./.cmk).
    if not (os.path.isdir(DST) and _plugin_sources(DST)):
        sys.stderr.write(
            "compose-mk: WARNING -- no CMK plugins bundled (repo-root .cmk/ submodule "
            "not found at %s; did you `git submodule update --init`?).  `cmk repl` and "
            "polyglot plugins will need a project-local ./.cmk.\n" % SRC
        )


_materialize()

# Install the materialized plugins under <prefix>/share/compose.mk/cmk/ (the `cmk`
# wrapper resolves this as <bin>/../share/compose.mk/cmk).  Sources are relative to
# HERE (== pip's build cwd) so they ride along in the sdist/wheel.
_bundled = [os.path.relpath(f, HERE) for f in sorted(glob.glob(os.path.join(DST, "*")))]

setup(
    # name / etc come from pyproject `[project]`; `script-files` from `[tool.setuptools]`.
    # version is `dynamic` in pyproject, so we resolve + supply it here (see `_version`).
    version=_version(),
    data_files=[("share/compose.mk/cmk", _bundled)] if _bundled else [],
)
