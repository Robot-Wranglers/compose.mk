# via/basher — install compose.mk on your PATH (via basher)

[basher](https://github.com/basherpm/basher) is a package manager for shell
(bash/zsh/fish) projects. Unlike `via/pip` and `via/npm`, **this folder needs no
packaging shim** — basher installs a whole repo and links the executables it
finds, and the repo-root `compose.mk` is already an executable (`100755`) at the
top level, so basher picks it up on its own.

This is **additive**: the normal drop-in usage (`include compose.mk` /
`./compose.mk`) is unchanged and remains the default; a global install is just a
convenience. See also `via/pip` and `via/npm`.

## Install

```bash
basher install Robot-Wranglers/compose.mk           # latest on the default branch
basher install Robot-Wranglers/compose.mk@v1.2.42   # pin a tag/branch/commit
```

basher clones the repo and links its executables onto your PATH. Its bin
autodiscovery is (in priority order): a `package.sh` `BINS=` list, else a `bin/`
directory, else **executable files in the repo root**. compose.mk has none of the
first two, so the third applies and links exactly `compose.mk`. The repo-root
`Makefile` is intentionally *not* executable (`100644`), so it is **not** linked —
only `compose.mk` lands on PATH. (Note basher keys off the executable *bit*, not
the presence of a shebang; if any other root file is ever `chmod +x`'d it would
be linked too.)

## Use after install

```bash
compose.mk flux.ok                 # tool mode
compose.mk mk.interpret! foo.cmk   # run a .cmk anywhere (CMK_SUPERVISOR=1)
```

In a project Makefile (library mode):

```make
_cmk := $(shell which compose.mk)
$(if $(_cmk),,$(error compose.mk not on PATH))
include $(_cmk)
```

## Requirements

Same runtime tools as the other install paths (basher only handles the
clone + PATH linking): `make`, `bash`, `jq`, and **GNU** `awk` (Debian: `gawk`, the
CMK compiler's awk stages need gawk, not `mawk`/busybox awk). basher itself needs
`git`. (No `ps`/`procps`: on Linux the supervisor self-detects `MAKE_CLI` from
`/proc`; `ps` is only used on macOS, which always ships it.)

The `basher-installer` tox env exercises all of this inside a `debian:bookworm-slim`
container (installing basher from git plus `make jq gawk`), so neither
basher nor npm/pip is ever assumed present on the host — only docker is. Because
basher can only *install* from a git remote and `basher link` symlinks the
package (which defeats basher's `find`-based root-executable autodiscovery), the
test stands in for `basher install` from the **local tree**: it materializes a
real package directory from the checkout and runs basher's own `_link-bins`, then
asserts `compose.mk` (and only `compose.mk`) is linked and works.
