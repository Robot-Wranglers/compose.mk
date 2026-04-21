# Changelog

## 0.4.0

- **Owned GNU Make base for `.cmk` files.** `source.cmk` was a standalone grammar that
  reimplemented only a subset of Make, so a `.cmk` file rendered *worse* than a plain
  Makefile (which rides VSCode's built-in makefile grammar). It now carries the base
  constructs it was dropping — mirroring the base the docs' Prism grammar already owns:
  - **Variable assignments** (`name := value`, also `?= += != = ::=`, incl. `export`/`override`
    forms and cmk's 2-space-indented block assignments) scope the name + operator.
  - **The Make function library** (`$(shell ..)`, `$(wildcard ..)`, `$(patsubst ..)`, `$(foreach ..)`,
    and the rest) scopes as `support.function.builtin.cmk`.
  - **Recipe → shell embedding.** Tab-indented recipe bodies now embed `source.shell` for real
    shell highlighting (`begin`/`while` spans the whole recipe block). The embed is
    *non-shadowing*: every cmk token rule that already colored recipe content (strings, banana,
    capture, make-refs, operators, keywords) is re-applied first, and `source.shell` only colors
    the plain-shell leftovers (`echo`, `for`, …). Note: matches the host makefile grammar's tab
    anchor; author-form 2-space cmk recipe bodies are a follow-up.
  - **Pseudo-paths** (`${mk.def.read}/hello_world`) split the `${..}` head from the `/tail`.
  - The new base uses standard TextMate scope names, so active color themes light them up
    without extra `configurationDefaults`.

- **Namespaced callform names.** `log.target(..)`, `cmk.log.io(..)`, `io.foo/bar` and the other
  cmk-namespace callforms — by far the most common kind of `.cmk` recipe line — now scope as
  `entity.name.function.namespaced.cmk` (previously unscoped). Restricted to the known cmk
  namespace roots so it never repaints an ordinary dotted shell/word token.

- **Constructors / named bananas.** Declaration heads now tokenize: a KIND-introducing keyword
  (`class`/`constructor`/`container`/`machine`/`dsl`/`factory`/`namespace`/`protocol`, plus
  `strategy`/`mixin`) scopes as `storage.type.cmk` and the name it mints as `entity.name.type.cmk`
  — for banana forms (`strategy portfolio(| .. |)`, `class Cook[| .. |]`) and bodyless heads
  (`container ubuntu`) alike. The name before any banana opener `(|`/`[|`/`{|` is scoped even for
  bare/user-KIND heads (`portfolio(| .. |)`, `jqlang git_status(| .. |)`). This also stops the
  greedy rule from mis-reading a banana body's `:` (e.g. inside a `sed` script or a target
  template) as a rule head. Previously none of this was scoped in either grammar.

- **Grammar tests.** A self-contained regression harness (`test/`, run with `npm test`) loads
  the grammar with VSCode's own `vscode-textmate` + `vscode-oniguruma` engine and asserts the
  scope of representative spans (assignments, `$(shell)`, recipe→shell, pseudo-paths, callform
  names, and the cmk constructs that must still win). Previously there were no grammar tests.

## 0.3.0

- **Default token colors.** The extension now ships `configurationDefaults` that layer
  bold/bright colors onto key cmk scopes over whatever color theme is active (previously the
  grammar assigned scopes but nothing colored them, so appearance depended entirely on the
  theme). Mirrors the docs site's `prism-cmk.base.css` emphasis:
  - banana-block delimiters `(| .. |)` render bright-white bold;
  - the `include` / `-include` / `sinclude` directive renders bright bold;
  - module-level `#` comments read one notch brighter than `@#` docstrings, with `##`
    doc-comments in a warm accent;
  - target names get bold + underline.
  - Tuned for dark themes; VSCode has no per-token font-size, so the docs' "bigger" tweaks
    are approximated with bold/underline. Override any rule in your own `settings.json`.

- **Emphasis decorations (`cmk.emphasis.style`).** The "more than theming" layer: decorations
  applied over banana-block delimiters `(| |)` and target names, since the grammar/theme cannot
  enlarge them. Selectable so each mechanism can be compared:
  - `off`, `bold` (default), `spacing` (bold + letter-spacing), `marker` (sized pseudo-element
    block beside the token), `box` (rounded outline) -- all fully supported.
  - `fontSize` -- an explicit opt-in to the UNSUPPORTED `textDecoration` CSS-injection hack. It
    makes the token **bigger** (`font-size`, via `cmk.emphasis.fontSizeScale`, default 1.6),
    **bolder** (`font-weight: 900`), and a **different font** (`cmk.emphasis.fontFamily`, default a
    serif stack) -- all three ride the injection because the structured decoration API exposes
    none of them. Line height does not reflow (large scales clip the line above and skew cursor
    geometry), so it carries a bold+spacing baseline and **degrades gracefully** to that if VSCode
    ignores the injected CSS (size/weight/family then revert to the editor defaults).

## 0.2.0

- **Shebang-aware run button.** A `$(play) run` CodeLens above every runnable target in a
  `.cmk` file. Clicking replays the file's shebang with the target appended (so
  `#!/usr/bin/env -S ./compose.mk cmk run` launches the target as `./file.cmk <target>` would),
  in an integrated terminal at the workspace root.
  - Anchored *above* a target's doc-block (contiguous `#` comments directly above it) so the
    button never interrupts the docs.
  - Refuses to run a file with no shebang (no defined launch path) instead of guessing.
  - Skips `%`-patterns, `.PHONY`-style specials, assignments, and indented module-local
    targets — only top-level literally-runnable goals get a button.
  - Toggle via the `cmk.showRunButton` setting.

## 0.1.0

Initial skeleton.

- `cmk` language + `source.cmk` TextMate grammar for `.cmk` files (comments, `##`
  doc-comments, `@#` docstrings, `# cmk_pragma` manifests, targets, `define`/`endef`,
  strings, `${...}`/`$$VAR`/`$(call ...)` variables, `import`/`declare` callforms,
  `__dunders__`, embed fences, integral/flow/sigil glyphs, recipe bashisms).
- `source.makefile.cmk-injection` injection grammar that adds the cmk extras on top of
  VSCode's built-in makefile grammar for `.mk` / `Makefile`.
- Scopes mirror the token taxonomy in `docs/theme/js/prism-cmk.js` (shared with the docs
  Prism grammar).
