# via/pip — install compose.mk on your PATH

This is a tiny packaging shim that installs the repo-root `compose.mk` as an executable on your `PATH` (the file here is a symlink to `../../compose.mk`, which stays the single source of truth). It exists so compose.mk can be used *globally* — without vendoring a copy into each project.

This is **additive**: the normal drop-in usage (download `compose.mk` into your project, `include compose.mk` / `./compose.mk`) is unchanged and remains the default. A global install is just a convenience.

## Install (primary method, no PyPI required)

```bash
pip install "git+https://github.com/robot-wranglers/compose.mk.git@<ref>#subdirectory=via/pip"
```

`<ref>` is a tag/branch/sha (e.g. `v1.2.3`). pip clones the repo, builds from this subdirectory, and drops `compose.mk` (plus a short `cmk` alias) into your environment's `bin/`.

## Use after install

```bash
compose.mk flux.ok                 # tool mode
compose.mk mk.interpret! foo.cmk   # run a .cmk anywhere (CMK_SUPERVISOR=1)

# `cmk` is the short CMK-language frontend -- exactly `compose.mk cmk`
# (the run | repl | build | compile | doc | cli dispatcher):
cmk foo.cmk                        # == `cmk run foo.cmk` (like `python foo.py`)
cmk run foo.cmk extra.target       # compile + run, passing extra make targets
cmk repl [foo.cmk]                 # interactive REPL over a program's namespace
cmk build foo.cmk                  # package a .cmk into a self-extracting binary
```

`cmk` is **not** a generic alias for the whole tool -- for core tool-mode
targets (`flux.ok`, `mk.interpret!`, ...) call `compose.mk` directly.

In a project Makefile (library mode):

```make
_cmk := $(shell which compose.mk)
$(if $(_cmk),,$(error compose.mk not on PATH))
include $(_cmk)
```

## Bundled plugins

The install also ships the stdlib CMK plugins (the repo-root `.cmk/` submodule:
`tux.repl.cmk`, `polyglot.golang.cmk`, `virtual-machine.cmk`, ...) into
`<prefix>/share/compose.mk/cmk/`, so plugin-dependent features (`cmk repl`, the
polyglot bridges) work from any directory. `setup.py` *copies* them in at build
time (not a symlink) so the sdist/wheel stays self-contained even when the
submodule isn't checked out at install time.

Plugin-dir precedence used by the `cmk` wrapper:

1. an explicit `CMK_PLUGINS_DIR` (env) — always wins;
2. a project-local `./.cmk` — a project's own plugins override the bundled set;
3. the bundled `<prefix>/share/compose.mk/cmk/` — the global fallback.

Note: this fallback is wired into the `cmk` wrapper only; calling the installed
`compose.mk` *directly* keeps the stock cwd-relative `./.cmk` default. There is
no plugin *search-path* (resolution is a single dir), so (2) and (3) don't merge
— a local `./.cmk` shadows the bundled set rather than augmenting it.

## Notes / limitations

- Linux-oriented (relies on the symlink + a POSIX `bin/`); Windows untested.
- For reproducibility, pin `<ref>`. The vendored/drop-in model remains available when you need a project-pinned copy.
