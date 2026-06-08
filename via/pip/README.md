# via/pip — install compose.mk on your PATH

This is a tiny packaging shim that installs the repo-root `compose.mk` as an executable on your `PATH` (the file here is a symlink to `../../compose.mk`, which stays the single source of truth). It exists so compose.mk can be used *globally* — without vendoring a copy into each project.

This is **additive**: the normal drop-in usage (download `compose.mk` into your project, `include compose.mk` / `./compose.mk`) is unchanged and remains the default. A global install is just a convenience.

## Install (primary method, no PyPI required)

```bash
pip install "git+https://github.com/robot-wranglers/compose.mk.git@<ref>#subdirectory=via/pip"
```

`<ref>` is a tag/branch/sha (e.g. `v1.2.3`). pip clones the repo, builds from this subdirectory, and drops `compose.mk` into your environment's `bin/`.

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

## Notes / limitations

- Linux-oriented (relies on the symlink + a POSIX `bin/`); Windows untested.
- For reproducibility, pin `<ref>`. The vendored/drop-in model remains available when you need a project-pinned copy.
