# via/npm: install compose.mk on your PATH (via npm)

A packaging shim that installs the repo-root `compose.mk` as an executable on your `PATH`, plus the short `cmk` alias and the stdlib CMK plugins. It exists so compose.mk can be used *globally*, without vendoring a copy into each project.

This is **additive**: the normal drop-in usage (download `compose.mk` into your project, `include compose.mk` / `./compose.mk`) is unchanged and remains the default.

## Install

From a checkout of this repo:

```bash
npm pack ./via/npm && npm install -g ./compose-mk-*.tgz
```

`npm pack` runs the `prepack` step, which stages the real files the tarball ships (see *Packaging* below). Installing the packed tarball is also exactly what a registry install does, so this is the path under test.

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

`cmk` is **not** a generic alias for the whole tool. For core tool-mode targets (`flux.ok`, `mk.interpret!`, ...) call `compose.mk` directly.

In a project Makefile (library mode):

```make
_cmk := $(shell which compose.mk)
$(if $(_cmk),,$(error compose.mk not on PATH))
include $(_cmk)
```

## Sandboxing

npm has no `activate` step, so scope an install one of these ways:

```bash
# per project: bin lands in node_modules/.bin, visible to npx and npm scripts
npm install ./via/npm && npx compose.mk flux.ok

# per prefix: an explicit tree you put on PATH yourself
npm install -g --prefix ~/.local/cmk ./compose-mk-*.tgz

# per node version: with nvm/volta/fnm active, plain -g is already scoped
npm install -g ./compose-mk-*.tgz
```

Each install carries its own bundled plugins, so two prefixes can hold two versions without interfering.

## Bundled plugins

The install ships the stdlib CMK plugins (the repo-root `.cmk/` submodule: `tux.repl.cmk`, `dsl.golang.cmk`, `virtual-machine.cmk`, ...) inside the package, so plugin-dependent features (`cmk repl`, the polyglot bridges) work from any directory.

Plugin-dir precedence used by the `cmk` wrapper:

1. an explicit `CMK_PLUGINS_DIR` (env) always wins;
2. a project-local `./.cmk` comes first on the search path, so a project's own plugins win name collisions and stay the writable staging dir;
3. the bundled set is appended, filling the gaps.

This fallback is wired into the `cmk` wrapper only. Calling the installed `compose.mk` directly keeps the stock cwd-relative `./.cmk` default.

## Packaging

npm's packer drops symlinks, so this shim cannot ship the repo-root `compose.mk` the way the pip shim does (as a checked-in symlink read through at build time). Instead `materialize.sh` runs from `prepack` and stages real bytes into a gitignored `_bundled/`:

| staged file            | source                  |
| ---------------------- | ----------------------- |
| `_bundled/compose.mk`  | the repo-root tool, via the checked-in `compose.mk` symlink |
| `_bundled/cmk`         | `../pip/cmk`, shared verbatim with the pip shim |
| `_bundled/plugins/`    | `*.mk` and `*.cmk` from the `.cmk/` submodule |

`package.json` points `bin` and `files` at that dir. Verify a build with:

```bash
npm pack ./via/npm --dry-run
```

## Notes / limitations

- The package version is the `0.0.0` placeholder in git; a release stamps it (`npm version --no-git-tag-version <x.y.z>`) before packing.
- Linux and macOS only; Windows untested.
- The vendored/drop-in model remains available when you need a project-pinned copy.
