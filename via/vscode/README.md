# cmk-lang — VSCode syntax highlighting

Syntax highlighting for **cmk-lang** (`.cmk`) and **enhanced highlighting for GNU
Makefiles** (`.mk` / `Makefile`), from the [compose.mk](https://github.com/Robot-Wranglers/compose.mk)
project.

cmk-lang is a superset of GNU Make: it keeps every Makefile construct (targets, `define`
blocks, `${...}`/`$(...)` variables, recipes) and adds a small layer of sugar — `# cmk_pragma`
manifests, `@#` recipe docstrings, `##` module doc-comments, `x.import(...)` / `declare.x(...)`
callforms, `__dunders__`, and flow glyphs.

## What it provides

1. **A full `cmk` language + grammar** (`source.cmk`) for `.cmk` files.
2. **An injection grammar** (`source.makefile.cmk-injection`) that layers the cmk-flavored
   extras *on top of* VSCode's built-in makefile grammar — so plain `.mk` / `Makefile`
   files get the cmk niceties (pragmas, doc-comments, callforms, dunders, glyphs) without
   replacing the base highlighting.
3. **A shebang-aware `run` button** (CodeLens) above every runnable target in a `.cmk`
   file — a better replacement for the generic Makefile run button.

### The run button

A `$(play) run` CodeLens sits above each target definition. Clicking it launches the target
by **replaying the file's own shebang** — so `#!/usr/bin/env -S ./compose.mk cmk run` runs the
target exactly the way executing `./file.cmk <target>` would, in an integrated terminal opened
at the workspace root.

- **Doc-blocks are respected.** When a run of `#` comment lines sits directly above a target,
  the button is anchored *above* the doc-block rather than wedged between the docs and the
  target they describe.
- **No shebang, no run.** A `.cmk` file with no `#!` line has no defined way to launch, so the
  runner refuses (with a message telling you to add one) instead of guessing.
- Patterns (`%`), `.PHONY`-style specials, variable assignments, and indented module-local
  targets are skipped — only top-level, literally-runnable goals get a button.
- Toggle with the **`cmk.showRunButton`** setting (default `true`).

Colors come from **whatever VSCode color theme you use** — this extension only assigns
standard TextMate **scopes**, so any theme colors it. There is no bundled color scheme.

## Single source of truth

The token → scope mapping is the same table that drives the docs' Prism grammar, living at
`docs/theme/js/prism-cmk.js` in the compose.mk repo (the `CMK TOKEN TAXONOMY` block). Both the
Prism grammar and these TextMate grammars are expressions of that one table — keep the scopes
in `syntaxes/*.json` in sync with it.

Representative scopes:

| construct | scope |
| --- | --- |
| target name | `entity.name.function.target.cmk` |
| `.PHONY`-style | `support.function.target.cmk` |
| `${...}` / `$(...)` | `variable.cmk` |
| `$$VAR` (shell) | `variable.other.shell.cmk` |
| `"..."` / `'''...'''` | `string.quoted.*.cmk` |
| `#` / `##` / `@#` comments | `comment.line.*.cmk` |
| `# cmk_pragma :::` | `meta.preprocessor.pragma.cmk` |
| `import`/`declare` callform | `meta.function-call.import-declare.cmk` |
| `define ... endef` | `meta.definition.makefile.cmk` |
| `__main__` | `constant.language.dunder.cmk` |
| compose key `image:` / `entrypoint=` | `keyword.other.compose.cmk` + `meta.value.compose.cmk` |
| flow arrows | `keyword.operator.{flow,sigil}.cmk` |

## Develop / try it locally

```bash
cd via/vscode
# open this folder in VSCode and press F5 to launch an Extension Development Host,
# then open a .cmk or .mk file.  Or symlink it into your extensions dir:
ln -s "$PWD" ~/.vscode/extensions/cmk-lang-dev
```

## Package / publish

```bash
npm install -g @vscode/vsce
cd via/vscode
vsce package          # -> cmk-lang-<version>.vsix   (install via "Extensions: Install from VSIX")
# vsce publish        # requires a marketplace publisher + token
```

## Layout

```
via/vscode/
  package.json                        extension manifest (languages, grammars, command, config)
  extension.js                        runtime: the shebang-aware run-button CodeLens provider
  language-configuration.json         comments / brackets / auto-close / define-block folding
  syntaxes/
    cmk.tmLanguage.json               full grammar for .cmk  (scopeName: source.cmk)
    cmk-makefile.injection.json       injection into source.makefile (enhanced .mk)
  README.md  CHANGELOG.md  .vscodeignore
```

## Status

v0.2.0 — full highlighting plus the shebang-aware run button. A future pass can derive the
grammars mechanically from the taxonomy table so Prism + TextMate never drift, add a bundled
grammar test harness (`vscode-tmgrammar-test`), and optionally extend the run button to
`makefile` documents.
