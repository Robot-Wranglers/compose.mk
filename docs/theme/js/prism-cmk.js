/*
 * prism-cmk.js -- the compose.mk (cmk / makefile) Prism language grammar, as a
 * SELF-CONTAINED component.  Extends Prism's stock `makefile` in place with the
 * shared compose.mk conventions, then defines `Prism.languages.cmk` (= makefile +
 * cmk-lang-only sugar).  Call `registerCmkGrammar(Prism)` after Prism has loaded
 * (idempotent); it also self-registers if Prism is already global at load time.
 *
 * The token TAXONOMY table below is the SINGLE SOURCE OF TRUTH (Prism today,
 * cmk.tmLanguage.json tomorrow).  Colors live in the swappable prism-cmk.<theme>.css
 * files + the achromatic prism-cmk.base.css -- NOT here.
 * See memory `cmk-syntax-highlighting-north-star`.
 */
(function (root) {
  function registerCmkGrammar(Prism) {
    if (!Prism || !Prism.languages || Prism.languages.cmk) return; // idempotent
        // ===================================================================
        // CMK TOKEN TAXONOMY -- single source of truth (Prism today, TextMate/
        // VSCode tomorrow).  Every custom token carries a STANDARD Prism alias so
        // (a) any stock Prism theme colors it and (b) it maps 1:1 to a TextMate
        // scope for the future `cmk.tmLanguage.json`.  Colors live in THEMES, not
        // here -- do not hardcode palette in the grammar.  See memory
        // `cmk-syntax-highlighting-north-star`.
        //
        //   token                 Prism alias    TextMate scope
        //   --------------------- -------------- -------------------------------
        //   comment               comment        comment.line.number-sign.cmk
        //   cmk-doc-comment ##     comment        comment.line.documentation.double.cmk
        //   string                string         string.quoted.cmk
        //   target                symbol         entity.name.function.target.cmk
        //   builtin-target        builtin        support.function.target.cmk
        //   variable              variable       variable.cmk
        //   keyword               keyword        keyword.control.cmk
        //   function              function       support.function.builtin.cmk
        //   operator              operator       keyword.operator.cmk
        //   punctuation           punctuation    punctuation.cmk
        //   keyword-include incl. keyword        keyword.control.import.include.cmk
        //   cmk-import            (container)    meta.import.namespace.cmk (import/open/from .. import .. except)
        //    - cmk-import-kw       keyword        keyword.control.import[.open].cmk (from/open/import/except)
        //    - keyword-as as       keyword        keyword.control.import.as.cmk
        //    - operator *          operator       keyword.operator.import.star.cmk (`from .. import *`)
        //    - cmk-import-ns <ns>  function       entity.name.namespace.cmk
        //   cmk-pragma            (container)    meta.preprocessor.pragma.cmk
        //    - cmk-pragma-kw       keyword        keyword.control.directive.cmk
        //    - cmk-pragma-div :::  punctuation    punctuation.definition.pragma.cmk
        //   cmk-module-call       (container)    meta.function-call.import-declare.cmk
        //    - cmk-module-call-name function      entity.name.function.cmk
        //    - callform-kv key=val (container)    meta.kwarg.cmk (key attr-name / = op / val attr-value)
        //   cmk-decorator @name(…) (container)    meta.decorator.cmk
        //    - cmk-decorator-sigil @ operator     keyword.operator.decorator.cmk
        //    - cmk-decorator-name  function       entity.name.function.decorator.cmk
        //    - cmk-decorator-arg   parameter      variable.parameter.cmk (bare positional)
        //    - callform-kv key=val (container)    meta.kwarg.cmk (kwargs, shared w/ module-call)
        //   cmk-decl-head         (container)    -- constructor/named-banana declaration head
        //    - cmk-decl-kw         keyword        storage.type.cmk (class/constructor/strategy/…)
        //    - cmk-decl-name       class-name     entity.name.type.cmk (the created KIND/type)
        //   cmk-banana-name        function       entity.name.function.cmk (name before (|/[|/{|)
        //   cmk-docstring @#...    comment        comment.line.documentation.cmk
        //   cmk-docstring-triple  string         string.quoted.docstring.cmk (line-leading ''' -- module/target __doc__; italic+muted)
        //   cmk-triple-string     string         string.quoted.triple.cmk
        //   cmk-syntax ▰         operator       keyword.operator.sigil.cmk
        //   cmk-capture <-        operator       keyword.operator.capture.cmk (bright/bold/oblique)
        //   cmk-line-feed 🡄 🡆 …   operator       keyword.operator.flow.cmk
        //   cmk-compose-keyword   keyword        keyword.control.dispatch.cmk
        //   cmk-dockerfile-kw     keyword        keyword.other.dockerfile.cmk
        //   cmk-dunder __main__ … constant       constant.language.dunder.cmk
        //   cmk-fpath ./path      string         string.unquoted.path.cmk
        //   cmk-fxn io. flux. …   function       entity.name.function.namespaced.cmk
        //   cmk-cli-token         builtin        support.constant.tool.cmk
        //   cmk-cli-keyword       builtin        support.function.cli.cmk
        //   cmk-args a,b,c        variable       variable.parameter.cmk
        //   cmk-recursion make …  keyword        variable.language.cmk
        //   shell-command echo …  builtin        support.function.shell.cmk
        //   shell-install apk …   builtin        support.function.shell.install.cmk
        //   backtick-content `…`  string         string.interpolated.cmk
        //   cmk-shebang #!        important       comment.line.shebang.cmk
        //   cmk-divider ░░░░…    comment        comment.line.divider.cmk (bold/bright/italic)
        //   -- pure-makefile base pass (targets/defines/macros/bashisms/strings) --
        //   target                (container)    meta.rule.cmk
        //    - rule-target         symbol         entity.name.function.target.cmk
        //    - rule-colon : ::     operator       punctuation.separator.key-value.cmk
        //    - prereq              symbol         entity.name.function.target.prereq.cmk
        //    - order-only |        operator       keyword.operator.order-only.cmk
        //   define-block          (container)    meta.definition.makefile.cmk
        //    - define-kw def/endef keyword        keyword.control.define.cmk
        //    - define-name         function       entity.name.function.define.cmk
        //   string-single '...'   string         string.quoted.single.cmk
        //   string-double "..."   string         string.quoted.double.cmk
        //   dollar-escape $$      constant       constant.character.escape.dollar.cmk
        //   auto-var $@ $< $^ …   variable       variable.language.automatic.cmk
        //   macro-call $(call x)  function       entity.name.function.macro.cmk
        //   shell-var $$VAR $${}  variable       variable.other.shell.cmk
        //   var-ref ${foo} $(foo) (container)    meta.variable.cmk
        //    - var-name           variable       variable.other.readwrite.cmk
        //   pseudo-path ${x}/tail (container)    meta.path.pseudo.cmk
        //    - pseudo-path-head    (container)    (var-ref: var-name + punctuation)
        //    - pseudo-path-tail    symbol         entity.name.path.tail.cmk
        //   heredoc << <<<        operator       keyword.operator.heredoc.cmk
        //   shell-operator && ; | operator       keyword.operator.shell.cmk
        //   recipe-prefix @ - +   operator       keyword.operator.recipe-prefix.cmk
        //   continuation  \       operator       punctuation.separator.continuation.cmk
        // ===================================================================
        // ---- BASE: compose-flavored makefile grammar ----------------------
        // Prism's stock `makefile` grammar, extended IN PLACE with the compose.mk
        // conventions shared by BOTH plain `.mk` and `.cmk` sources (namespaced
        // calls, glyphs, embed fences, pragmas, docstrings, dispatch, targets,
        // shell builtins).  This is the BASELINE MAKEFILE: improve it here and --
        // via the `extend` below -- the improvement flows into `cmk` too.  `.mk`
        // demo blocks (language-Makefile) use THIS grammar.  NOTE: we NO LONGER touch
        // Prism's `bash`/`make` languages -- `cli_example` (language-bash) blocks get
        // PLAIN, orthogonal Prism bash highlighting, uninvolved with the cmk grammar.

        // Reusable token defs (used on the base and/or on cmk below).
        var cmkPragmaDef = {
            pattern: /#[ \t]*(?:CMK_PRAGMA|cmk_pragma)[ \t]*:::[\s\S]*?:::/,
            greedy: true,
            inside: {
                'cmk-pragma-div': { pattern: /:::/, alias: 'punctuation' },
                'cmk-pragma-kw': { pattern: /\b(?:CMK_PRAGMA|cmk_pragma)\b/, alias: 'keyword' },
                'comment': /^[ \t]*#/m,
                'property': { pattern: /"(?:\\.|[^\\"\r\n])*"(?=[ \t]*:)/, greedy: true },
                'string': { pattern: /"(?:\\.|[^\\"\r\n])*"/, greedy: true },
                'boolean': /\b(?:true|false)\b/,
                'null': { pattern: /\bnull\b/, alias: 'keyword' },
                'number': /-?\b\d+(?:\.\d+)?\b/,
                'punctuation': /[{}[\],:]/,
            },
        };
        var cmkModuleCallDef = {
            pattern: /^(?:[\w+-]+\.)*(?:import|declare)(?:\.[\w+-]+)*[ \t]*\([^\r\n)]*\)/m,
            greedy: true,
            inside: {
                'cmk-module-call-name': { pattern: /^[\w.+-]+/, alias: 'function' },
                // `key=value` kwargs inside the callform parens -> callform-kv (key -> attr-name,
                // `=` -> operator, value -> attr-value; inner ${..} still highlights).  BEFORE the
                // standalone `variable`/`string` so it claims the whole pair first (else those
                // grab a `${..}`/`"..."` value globally, leaving a bare `key=`).
                'callform-kv': {
                    pattern: /[\w.+-]+=[^\s()]*/,
                    inside: {
                        'attr-name': /^[\w.+-]+/,
                        'operator': /=/,
                        'variable': /\$\{[^{}]*\}|\$+\w+/,
                        'attr-value': /[^\s()]+/,
                    },
                },
                'variable': /\$\{[^{}]*\}|\$+\w+/,
                'string': { pattern: /'[^'\r\n]*'|"[^"\r\n]*"/, greedy: true },
                'cmk-syntax': { pattern: /▰/, alias: 'operator' },
                'punctuation': /[()]/,
            },
        };
        // cmk-lang-ONLY defs (layered onto `cmk` alone, below).
        var cmkTripleDef = { 'cmk-triple-string': {
            pattern: /"""[\s\S]*?"""|'''[\s\S]*?'''/,
            greedy: true, alias: 'string',
            inside: {
                'variable': /\$\{[^{}]*\}|\$+\w+/,
                'attr-name': /[\w.+-]+(?==)/,
                'operator': /=/,
                'punctuation': /"""|'''/,
            } } };
        // Pythonic DOCSTRING: a triple-quote group that OPENS a line -- col-0 is the module
        // `__doc__`, a tab-indented first recipe line is a target docstring.  Distinct from an
        // inline triple-string VALUE (which follows `=`/`(`/a command and is not line-leading),
        // so it reads muted + italic like an editor docstring.  Same inner rules as the generic
        // triple-string; inserted BEFORE cmk-triple-string so it claims the line-leading case.
        var cmkDocstringTripleDef = { 'cmk-docstring-triple': {
            pattern: /^[ \t]*(?:"""[\s\S]*?"""|'''[\s\S]*?''')/m,
            greedy: true, alias: 'string',
            inside: {
                'variable': /\$\{[^{}]*\}|\$+\w+/,
                'attr-name': /[\w.+-]+(?==)/,
                'operator': /=/,
                'punctuation': /"""|'''/,
            } } };
        var cmkLineFeedDef = { 'cmk-line-feed': {
            pattern: /(\\|▰|\$|ᐉ|🡄|🡆|⬦|⬥)/, alias: "operator cmk-syntax" } };
        // the `<-` CAPTURE operator, split OUT of the grey cmk-line-feed glyphs into its own
        // token so it can be lifted EXTREMELY bright + bold + oblique (see base.css).  Lookbehind
        // `(?<![<$])` keeps `<<-` heredocs / `$<` auto-vars from mis-firing.  Own alias `operator`
        // (NO cmk-syntax) so the grey glyph rule skips it.
        var cmkCaptureDef = { 'cmk-capture': {
            pattern: /(?<![<$])<-/, alias: 'operator' } };
        // the `&NAME` HANDLE bind LHS -- the `&` marks a DEFERRED bind (`&bound <- ..`): store
        // the callable but do NOT run it.  Split into a `&` sigil + the handle name so the name
        // reads as a variable (not swallowed as text) and the `&` isn't mis-tagged as the shell
        // `&&`/background operator.  A trailing `<-` lookahead scopes it to the bind site ONLY, so
        // a YAML anchor (`alice: &base`) inside an inlined compose file is left alone.
        var cmkHandleDef = { 'cmk-handle': {
            pattern: /(?<![\w&])&[A-Za-z_][\w.+-]*(?=[ \t]*<-)/,
            inside: {
                'cmk-handle-sigil': { pattern: /^&/, alias: 'operator' },
                'cmk-handle-name': { pattern: /[\w.+-]+/, alias: 'variable' },
            } } };
        // Paired banana-block delimiters, PROMOTED out of the grey cmk-syntax glyphs.
        // Own tokens (alias `operator`, NO cmk-syntax) so the grey rule skips them.
        var cmkPairGlyphs = {
            // banana-block delimiters: `(| .. |)` (raw), `[| .. |]` (deep-cook),
            // `{| .. |}` (pragma-configurable treatment)
            'cmk-banana': { pattern: /[([{]\||\|[)\]}]/, alias: 'operator' },
            // the `{env}` callform/trailer channel `{k=v ..}` (a brace group with an `=`;
            // distinct from `${..}` make refs, which carry no bare `=` inside)
            'cmk-env': { pattern: /\{[^{}\r\n]*=[^{}\r\n]*\}/, alias: 'operator' },
        };
        // `@name(args)` binding/annotation DECORATOR (e.g. `@args.from_json(shape color=blue
        // name=default)`, `@fault.guarded`): the `@` sigil + a dotted name + optional callform
        // args -- bare positional params and `key=value` kwargs.  Split so each part scopes
        // distinctly (kwargs reuse the callform-kv shape).  Inserted EARLY (before the base
        // operator/punctuation) so the inner `=` isn't fragmented out of the parens.
        // The `@` is COLUMN 0 ONLY (line-start lookbehind), so a recipe `\t@echo` is untouched.
        var cmkDecoratorDef = { 'cmk-decorator': {
            pattern: /(?<=^|[\r\n])@[\w.+-]+(?:[ \t]*\([^()\r\n]*\))?/,
            greedy: true,
            inside: {
                'cmk-decorator-name': {
                    pattern: /^@[\w.+-]+/,
                    alias: 'function',
                    inside: {
                        'cmk-decorator-sigil': { pattern: /^@/, alias: 'operator' },
                    },
                },
                'callform-kv': {
                    pattern: /[\w.+-]+=[^\s()]*/,
                    inside: {
                        'attr-name': /^[\w.+-]+/,
                        'operator': /=/,
                        'variable': /\$\{[^{}]*\}|\$+\w+/,
                        'attr-value': /[^\s()]+/,
                    },
                },
                'variable': /\$\{[^{}]*\}|\$+\w+/,
                'string': { pattern: /'[^'\r\n]*'|"[^"\r\n]*"/, greedy: true },
                'cmk-decorator-arg': { pattern: /[\w.+-]+/, alias: 'parameter' },
                'punctuation': /[()]/,
            },
        } };

        // Receiver STREAM-form name (`inbox.emit[...]`, `this.b[...]`): a dotted name
        // immediately before a `[` stream bracket -- the receiver being piped INTO.  Same
        // `function` alias + `cmk-fxn` brightness as the other callform names (see base.css),
        // so `inbox.emit` reads as brightly as `cmk.log.io(...)`.  First char is not a dot
        // (so a leading `.member` after a `this` keyword isn't grabbed as its own name).
        var cmkReceiverDef = { 'cmk-receiver-name': {
            pattern: /[\w+-][\w.+-]*(?=\[)/,
            alias: 'function',
        } };

        // -- shared compose.mk tokens on the makefile base (+ bash examples) --
        // word-anchored (was `/.*(stop|build|ps) /`, which keyworded the WHOLE line up to
        // the subcommand -- e.g. any recipe/example line containing "build").
        var compose_keywords = { 'cmk-compose-keyword': { pattern: /\b(?:stop|build|ps)\b/, alias: "keyword" } };
        Prism.languages.insertBefore('makefile', 'keyword',
            { 'cmk-dockerfile-kw': { pattern: /(RUN |FROM |ENV |SHELL |ENTRYPOINT |COMMAND )/, alias: "keyword" } });

        var cmk_cli_token = { 'cmk-cli-token': { pattern: / (?:compose[.]mk|[.]\/compose.mk)/, alias: "builtin" } };
        Prism.languages.insertBefore('makefile', 'keyword', cmk_cli_token);

        var cmk_glyphs = { 'cmk-syntax': { pattern: /(▰|\$)/, alias: "operator" } };
        Prism.languages.insertBefore('makefile', 'punctuation', cmk_glyphs);


        var cmk_docstring = { 'cmk-docstring': { pattern: /@#[^\r\n]*/, alias: "comment" } };
        Prism.languages.insertBefore('makefile', 'comment', cmk_docstring);

        // (triple-strings + flow glyphs are cmk-lang sugar, layered onto `cmk` below.)

        var cmk_dispatch = { 'cmk-compose-keyword': { pattern: /([.](dispatch)(\\|,))/, alias: "keyword" } };
        Prism.languages.insertBefore('makefile', 'keyword', cmk_dispatch);
        Prism.languages.insertBefore('makefile', 'punctuation', cmk_dispatch);
        var cmk_run = { 'cmk-compose-keyword': { pattern: /[.](run).*/, alias: "keyword" } };
        Prism.languages.insertBefore('makefile', 'keyword', cmk_run);
        // cmk-lang namespace directives (MIRROR: via/vscode/syntaxes/cmk.tmLanguage.json
        // `#cmk-import`).  Col-0 forms, differing by INTENT:
        //   `import <ns>[, <ns2>]`                        -- USE ns (assert-resolves)
        //   `open   <ns>[, <ns2>] [except A B]`           -- MODIFY ns (load-if-exists; drop names)
        //   `import <src>[, ..] as <ns>[, ..] [kw=v..]`   -- load source(s) + route namespace(s)
        //   `from <mod> import <*|A,B> [except A B]`       -- Pythonic selective bind of a module's members
        //   cmk-import-kw from/open/import/except keyword  keyword.control.import[.open].cmk
        //   keyword-as    as           keyword     keyword.control.import.as.cmk
        //   cmk-import-ns <ns>/<src>   function    entity.name.namespace.cmk
        //   callform-kv   kw=v         (container) meta.kwarg.cmk (trailing kwargs)
        var cmk_import = { 'cmk-import': {
            pattern: /^[ \t]*(?:from[ \t]+[\w.+-]+[ \t]+import[ \t]+(?:\*|[\w.+-]+(?:[ \t]*,[ \t]*[\w.+-]+)*)(?:[ \t]+except[ \t]+[\w.+-]+(?:[ \t]*,?[ \t]*[\w.+-]+)*)?|open[ \t]+[\w./+-]+(?:[ \t]*,[ \t]*[\w./+-]+)*(?:[ \t]+except[ \t]+[\w.+-]+(?:[ \t]*,?[ \t]*[\w.+-]+)*)?|import[ \t]+[\w./+-]+(?:[ \t]*,[ \t]*[\w./+-]+)*(?:[ \t]+as[ \t]+[\w.+-]+(?:[ \t]*,[ \t]*[\w.+-]+)*)?(?:[ \t]+[\w.+-]+=[^\r\n]*)?)[ \t]*$/m,
            inside: {
                // leading directive keyword (from/open/import) + the mid-line `import`/`except`
                // of the `from .. import .. except ..` form (space-anchored so a member/ns named
                // `import`/`except` in the list isn't mis-tagged).
                'cmk-import-kw': { pattern: /(?:^[ \t]*(?:from|open|import)|(?<=[ \t])(?:import|except))\b/, alias: 'keyword' },
                // `as` (only meaningful between the source-list and the ns-list): space-anchored
                // so a `path/as/x` segment or a namespace containing `as` isn't mis-tagged.
                'keyword-as': { pattern: /(?<=[ \t])as(?=[ \t])/, alias: 'keyword' },
                // the `import *` wildcard (bind all of the module's prelude members).
                'operator': /\*/,
                // trailing `kw=value` kwargs (import..as form only) -- reuse the module-call shape.
                'callform-kv': {
                    pattern: /[\w.+-]+=\S*/,
                    inside: {
                        'attr-name': /^[\w.+-]+/,
                        'operator': /=/,
                        'variable': /\$\{[^{}]*\}|\$+\w+/,
                        'attr-value': /\S+/,
                    },
                },
                'punctuation': /,/,
                'cmk-import-ns': { pattern: /[\w./+-]+/, alias: 'function' },
            },
        } };
        Prism.languages.insertBefore('makefile', 'keyword', cmk_import);

        // `include` / `-include` / `sinclude` directive: SPLIT out of the stock `keyword`
        // lump so it can be lifted BRIGHTER than ordinary keywords (see base.css's
        // `.token.keyword-include`).  Inserted BEFORE `keyword` so it claims the word first;
        // alias `keyword` keeps its theme hue.  MIRROR: cmk.tmLanguage.json `#cmk-include`.
        var cmk_include = { 'keyword-include': {
            pattern: /(?<![\w-])(?:-include|sinclude|include)\b/, alias: 'keyword' } };
        Prism.languages.insertBefore('makefile', 'keyword', cmk_include);

        Prism.languages.insertBefore('makefile', 'target',
            { 'cmk-dunder': { pattern: /(__main__|__init__|__name__)/, alias: "constant" } });
        Prism.languages.insertBefore('makefile', 'target',
            { 'cmk-dockerfile-kw': { pattern: /(RUN|FROM)/, alias: "keyword" } });

        // Variable assignment `name = value` (incl. `:=` `::=` `?=` `+=` `!=`).  Matched
        // as a WHOLE LINE so the `:` in a docker-image-style value (`name=repo:tag`) is
        // NOT mistaken for a rule separator: key -> attr-name (a k=v key, same as the
        // module-call kwargs), the assign op -> operator, and a `repo:tag` value splits
        // into repo (attr-value) `:` (punctuation) tag (string).  Restricted to SIMPLE
        // word values (no spaces / `$(...)`) so complex assignments keep the normal
        // makefile highlighting.  On the BASE grammar -> inherited by cmk (the .cmk twin).
        Prism.languages.insertBefore('makefile', 'target', {
            'cmk-assignment': {
                pattern: /^[\w.+-]+[ \t]*(?::{1,3}|[?+!])?=[ \t]*[\w.+-]+(?::[\w.+-]+)*[ \t]*$/m,
                inside: {
                    'attr-name': /^[\w.+-]+/,
                    'operator': /(?::{1,3}|[?+!])?=/,
                    'cmk-value-tag': { pattern: /(?<=:)[\w.+-]+/, alias: 'string' },
                    'punctuation': /:/,
                    'attr-value': /[\w.+-]+/,
                },
            },
        });

        // pragma / shebang / dockerfile + the import/declare callforms (shared;
        // these appear in .mk and .cmk alike).
        Prism.languages.insertBefore('makefile', 'comment', {
            // decorative section-divider: a run of 4+ `░` light-shade chars ("more than 3
            // in a row"), usually a `#`/`##`-prefixed section rule.  FIRST here so it wins
            // over cmk-doc-comment/comment (which would otherwise swallow the whole line);
            // styled bold/bright/italic in base.css.  MIRROR: cmk.tmLanguage.json `#divider`.
            'cmk-divider': { pattern: /#*░{4,}/, greedy: true },
            'cmk-pragma': cmkPragmaDef,
            'cmk-module-call': cmkModuleCallDef,
            // anchored to the START of the block (no /m): a real `#!` shebang is line 1,
            // so this no longer fires on `#!` inside define bodies / mid-recipe.
            'cmk-shebang': { pattern: /^#![^\r\n]*/, alias: "shebang important" },
            // `## ...` doc-comments (compose.mk's module/target documentation convention)
            // are distinct from ordinary `# ...` comments -- own token so they can render
            // bigger (see base.css).  Before stock `comment` so `##` wins over `#`.
            'cmk-doc-comment': { pattern: /^[ \t]*##[^\r\n]*/m, alias: "comment" },
            'cmk-dockerfile': { pattern: /(?<=Dockerfile.).*?(?=[ \n])/g, alias: "important" },
        });

        // A2 -- `define NAME ... endef` blocks, grammar-driven (replaces a dead DOM walk).
        // Wraps the whole block (wrapper alias `inside-define` -> a subtle panel in base.css),
        // tags `define`/`endef` + the NAME, and re-applies the makefile grammar to the body
        // (via `rest`) so targets/vars/comments -- and foreign-embed keywords -- still light
        // up.  BEFORE `comment` so `#`/`foo:` on the define line don't pre-empt the block.
        Prism.languages.insertBefore('makefile', 'comment', {
            'define-block': {
                pattern: /^[ \t]*define[ \t]+.*\r?\n[\s\S]*?^[ \t]*endef\b/m,
                greedy: true,
                alias: 'inside-define',
                inside: {
                    // define-name FIRST: its `define `-lookbehind needs `define` intact
                    // (define-kw would otherwise consume it), leaving `define ` as text
                    // that define-kw then tags.
                    'define-name': { pattern: /(^[ \t]*define[ \t]+)[^\r\n]+/m, lookbehind: true, alias: 'function' },
                    'define-kw': { pattern: /^[ \t]*(?:define|endef)\b/m, alias: 'keyword' },
                    'rest': Prism.languages.makefile,
                },
            },
        });


        // target names EXCLUDE `=` so a variable assignment (`x=python:3.11`) whose value
        // contains `:` is not greedily grabbed as a rule target (was `[^\s:]+`).
        // Structured rule head: NAME(s) up to the `:`/`::` (never `:=`) + prerequisites.
        // Splits rule NAME (rule-target) from the colon (rule-colon) from the deps
        // (prereq) so they can be weighted differently (achromatic, see base.css).  The
        // outer NAME part must not cross `=` (so assignment LHS isn't grabbed); prereqs
        // run to EOL or an inline `;`-recipe.  Not tab-indented (recipes), not `#`.
        Prism.languages.makefile.target = {
            // tail: after the `:`/`::`, either an inline-recipe `;` (the `target:;` form) OR
            // ordinary prerequisites -- so the `;` is captured as part of the rule head.  The
            // `(?![^:=\r\n]*[([{]\|)` lookahead REFUSES the match when a banana opener (`(|`/
            // `[|`/`{|`) precedes the colon -- a real target head never has one, so a KIND-
            // prefixed named-banana head (`jqlang wrap(|   { result: . } |)`) is not mis-read as
            // a target up to the `:` inside the (jq) body.  (`target` is greedy, so it would
            // otherwise overrun the `cmk-banana-name` token that tagged the instance name.)
            pattern: /^(?!\t)(?![^:=\r\n]*[([{]\|)[^\s:=#][^\r\n=]*?::?(?!=)(?:;|[^\r\n;]*)/m,
            greedy: true,
            inside: {
                'builtin-target': { pattern: /^\.[A-Z][A-Za-z]+\b/, alias: 'builtin' },
                'rule-target': {
                    pattern: /^[^:\r\n]+?(?=[ \t]*::?(?!=))/,
                    alias: 'symbol',
                    inside: {
                        // box-drawing / tree glyphs (├ ─ │ └ ...) in a name: own token so the
                        // rule-target underline can be lifted off them (see base.css).
                        'target-glyph': { pattern: /[─-╿]+/, alias: 'punctuation' },
                        'variable': /\$\{[^{}]*\}|\$\([^()]*\)|\$[@*<^?+|%]/,
                        'operator': /%/,
                        'punctuation': /\//,
                    },
                },
                // `:;` (empty-recipe / inline-recipe marker) -- distinct so it renders at full
                // brightness; must precede plain rule-colon.
                'rule-colon-recipe': { pattern: /::?;(?!=)/, alias: 'operator' },
                'rule-colon': { pattern: /::?(?!=)/, alias: 'operator' },
                'variable': /\$\{[^{}]*\}|\$\([^()]*\)|\$[@*<^?+|%]/,
                'order-only': { pattern: /\|/, alias: 'operator' },
                'prereq': { pattern: /[^\s|]+/, alias: 'symbol' },
            },
        };

        var cmk_cli_keywords = { 'cmk-cli-keyword': { pattern: /\b(loadf|jb|jq)\b/, alias: "builtin" } };

        // cmk-args (any `a,b,c` -> variable) is retired from the makefile BASE -- it
        // repainted ordinary comma lists and `$(call x,a,b)` args, hurting pure-makefile
        // fidelity and pre-empting `macro-call`.  Kept on bash for CLI-example blocks.
        var cmk_args = { 'cmk-args': { pattern: /(?:[\w.-]+)(?:,(?:[\w.-]+))+/, alias: "variable" } };

        // Shared "expansion" inner-grammar: make ${..}/$(..)/$@ and shell $$VAR/$${..}
        // that must keep highlighting INSIDE double-quoted strings + backticks.
        var cmkExpandInside = /\$\$\{[^{}]*\}|\$\$[A-Za-z_]\w*|\$\{[^{}]*\}|\$\([^()]*\)|\$[@*<^?+|]/;

        // Stock `makefile` lumps `"..."` and `'...'` into one `string` with NO inside, so
        // `${..}`/`$(..)` inside a double-quoted string are swallowed.  Split them: single
        // quotes stay literal (shell semantics); double quotes keep inner expansions lit.
        // Inserted BEFORE stock `string` (which survives as the cmk triple-string anchor).
        Prism.languages.insertBefore('makefile', 'string', {
            'string-single': { pattern: /'(?:\\.|[^\\'\r\n])*'/, greedy: true, alias: 'string' },
            'string-double': {
                pattern: /"(?:\\.|[^\\"\r\n])*"/, greedy: true, alias: 'string',
                inside: { 'variable': cmkExpandInside, 'punctuation': /"/ },
            },
        });

        // shared recipe-body tokens on the makefile base.
        Prism.languages.insertBefore('makefile', 'keyword', {
            'backtick-content': { pattern: /`[^`\n]*`/, alias: "string", inside: { 'variable': cmkExpandInside, 'punctuation': /`/ } },
            // `this` only fires as a receiver keyword when followed by `.` so
            // `this_directory` / bare `this ` stay plain identifiers.
            'cmk-recursion': { pattern: /\b(?:make|self)|\bthis(?=\.)/, alias: "keyword" },
            // word-anchored so `run`/`dispatch` don't fire INSIDE a longer word (e.g.
            // the `run` in `runtime`, or a `.run`-prefixed member).
            'cmk-syntax': { pattern: /\b(?:dispatch|run)\b|compose[.]import.* /, alias: "operator" },
            'shell-command': { pattern: /(?:echo|cat|apk|wget|tar|apt-get|pip3|pip|npm|ansible) /, alias: "builtin" },
            'shell-install': { pattern: /(?:apk|apt-get) /, alias: "builtin" },
            'cmk-fxn': { pattern: /(?:io|log|cmk|docker|Dockerfile|flux|stage|mk|stream|tux)[.]([a-z._])+(?:(\/|,|\())/, alias: "function" },
        });

        // parenthesized namespaced call `cmk.log.json(args)`: split the NAME (cmk-fxn,
        // brightened in base.css) from its ARGS (cmk-fxn-args, italic via the `italic` alias;
        // inner `${..}` still highlighted).  Inserted BEFORE `variable` so a `${..}` arg doesn't
        // get claimed first and fragment the call.  Simple args only; nested-paren args
        // (`$(shell ..)`) fall back to the bare `cmk-fxn` above (name-only, as before).
        Prism.languages.insertBefore('makefile', 'variable', {
            'cmk-fxn-call': {
                pattern: /(?:io|log|cmk|docker|Dockerfile|flux|stage|mk|stream|tux)[.][\w.]+\([^()\r\n]*\)/,
                inside: {
                    'cmk-fxn': { pattern: /^[\w.]+/, alias: 'function' },
                    'cmk-fxn-args': { pattern: /[^()]+/, alias: 'italic', inside: { 'variable': /\$\{[^{}]*\}|\$+\w+/ } },
                    'punctuation': /[()]/,
                },
            },
        });

        // A3 -- macros / expansion.  Inserted BEFORE `variable` so these win over the
        // stock catch-all variable token: `$${VAR}`/`$$VAR` (shell vars written doubled
        // for make), the literal `$$` escape, automatic vars ($@ $< $^ ...), and the
        // invoked NAME in `$(call name,...)` (the `$(call ` stays a stock function).
        // BASH var (`$$VAR` / `$${VAR}` / `$${VAR:-default}` / `$${VAR#pat}`) -- distinct
        // from the MAKE var-ref (alias `bash-var`).  Interior tokenized like a key=value:
        // NAME -> attr-name, parameter-expansion OP (`:-` `:=` `#` `##` `%` `%%` `//` ...) ->
        // operator, operand -> attr-value.  Inserted BEFORE `comment` so a `#` param-strip
        // op inside `$${VAR#...}` isn't mistaken for a comment.
        Prism.languages.insertBefore('makefile', 'comment', {
            'shell-var': {
                pattern: /\$\$\{[^{}]*\}|\$\$[A-Za-z_]\w*/,
                alias: 'variable bash-var',
                inside: {
                    'dollar': { pattern: /^\$\$/, alias: 'punctuation' },
                    'param-expansion': {
                        pattern: /(?::[-=?+]?|##?|%%?|\/\/?|\^\^?|,,?)[^{}]*/,
                        inside: {
                            'operator': /^(?::[-=?+]?|##?|%%?|\/\/?|\^\^?|,,?)/,
                            'attr-value': /[^{}]+/,
                        },
                    },
                    'attr-name': /[A-Za-z_]\w*/,
                    'punctuation': /[{}]/,
                },
            },
        });

        Prism.languages.insertBefore('makefile', 'variable', {
            'dollar-escape': { pattern: /\$\$(?![({\w])/, alias: 'constant' },
            'auto-var': { pattern: /\$[@*<^?+|]|\$\([@*<^?+|][DF]\)/, alias: 'variable' },
            'macro-call': { pattern: /(\$\(call[ \t]+)[\w.+-]+/, lookbehind: true, alias: 'function' },
            // `${mk.def.read}/hello_world` -- a var-ref used like a path (a compose.mk idiom).
            // Split into pseudo-path-head (the `${...}`) and pseudo-path-tail (the `/name`).
            // BEFORE `var-ref` so the head isn't consumed as a bare var-ref first.
            'pseudo-path': {
                pattern: /\$[{(][\w.+-]+[})]\/[\w.+*?\/-]+/,
                inside: {
                    'pseudo-path-head': {
                        pattern: /^\$[{(][\w.+-]+[})]/,
                        inside: {
                            'dollar': { pattern: /^\$/, alias: 'punctuation' },
                            'punctuation': /[{}()]/,
                            'var-name': { pattern: /[\w.+-]+/, alias: 'variable' },
                        },
                    },
                    'pseudo-path-tail': {
                        pattern: /\/[\w.+*?\/-]+/,
                        alias: 'symbol',
                        inside: {
                            'punctuation': /\//,
                            'operator': /[*?]/,   /* glob wildcards, e.g. `/*.md` */
                        },
                    },
                },
            },
            // `${foo}` / `$(foo)` variable references: split the `${`/`}` delimiters from
            // the NAME (var-name) so the inner ref is its own token.  Restricted to plain
            // identifiers so `$(shell ...)` / `$(call ...)` (spaces) stay function calls.
            'var-ref': {
                pattern: /\$[{(][\w.+-]+[})]/,
                alias: 'variable make-var',
                inside: {
                    'dollar': { pattern: /^\$/, alias: 'punctuation' },
                    'punctuation': /[{}()]/,
                    'var-name': { pattern: /[\w.+-]+/, alias: 'variable' },
                },
            },
        });

        // A4 -- common recipe bashisms (targeted, NOT a full embedded bash grammar --
        // that would fight make tokens).  Inserted BEFORE `keyword`.
        Prism.languages.insertBefore('makefile', 'keyword', {
            'heredoc': { pattern: /<<<?-?[ \t]*['"]?[\w.-]+['"]?/, alias: 'operator' },
            'shell-operator': { pattern: /&&|\|\||[|&;]/, alias: 'operator' },
            'recipe-prefix': { pattern: /(?<=^\t)[-@+]+/m, alias: 'operator' },
            'continuation': { pattern: /\\$/m, alias: 'operator' },
        });

        // ---- cmk = makefile base + cmk-lang-only sugar --------------------
        // extend() DEEP-CLONES the fully-built makefile above, so `cmk` inherits
        // every base token (and any future base improvement applied before this
        // line).  The cmk-lang-only sugar below is layered on `cmk` ALONE, so it
        // never leaks into plain makefile/bash blocks -- this is where to improve
        // cmk independently.  (`.cmk` demo blocks use language-cmk; see site.j2.)
        Prism.languages.cmk = Prism.languages.extend('makefile', {});
        // triple-string must precede the split string-single/string-double (base A5) so
        // `"""..."""` / `'''...'''` win over the single/double tokens in cmk blocks.
        Prism.languages.insertBefore('cmk', 'string-single', cmkTripleDef);
        // line-leading docstring runs BEFORE the generic triple-string so it claims a col-0 /
        // first-recipe-line `'''...'''` (module or target `__doc__`) as its own muted token.
        Prism.languages.insertBefore('cmk', 'cmk-triple-string', cmkDocstringTripleDef);
        Prism.languages.insertBefore('cmk', 'punctuation', cmkLineFeedDef);
        // capture `<-` runs BEFORE cmk-line-feed so it claims the arrow as its own bright token.
        Prism.languages.insertBefore('cmk', 'cmk-line-feed', cmkCaptureDef);
        // handle `&NAME` bind LHS runs BEFORE the inherited `shell-operator` (which matches a bare
        // `&`), so `&bound` is claimed whole (sigil + name) instead of `&` being tagged as the
        // shell background/`&&` operator with `bound` left as plain text.
        Prism.languages.insertBefore('cmk', 'shell-operator', cmkHandleDef);
        // banana-block delimiters must run BEFORE the grey `cmk-syntax` glyph token that also
        // matches them, so they claim `(|`/`|)` etc. as their own (white) tokens.
        Prism.languages.insertBefore('cmk', 'cmk-syntax', cmkPairGlyphs);
        // decorator runs EARLY (before comment/operator) so `@name(k=v ...)` is claimed as
        // one token before the base `=`/punctuation tokens can fragment its kwargs.
        Prism.languages.insertBefore('cmk', 'comment', cmkDecoratorDef);
        // receiver name runs late (after comment/string/triple-string are claimed) but before
        // `punctuation` grabs the `[`, so only a real `name[` in code is caught.
        Prism.languages.insertBefore('cmk', 'cmk-line-feed', cmkReceiverDef);
        // constructor / named-banana declaration heads (MIRROR: cmk.tmLanguage.json `#decl-head`
        // + `#banana-name`).  A KIND-introducing keyword + the name it creates (`class Cook`,
        // `strategy portfolio(| .. |)`, bodyless `container ubuntu`), and any name immediately
        // before a banana opener `(|`/`[|`/`{|` (bare `portfolio(| .. |)`, user-KIND head
        // `jqlang git_status(| .. |)`).  Inserted BEFORE `target` so the name wins over the
        // greedy rule head -- which would otherwise swallow `component(| $(1).build` (up to a `:`
        // inside the banana body / a sed script) as one bogus target.
        Prism.languages.insertBefore('cmk', 'target', {
            'cmk-decl-head': {
                // an optional trailing callform `(k=v ..)` is consumed here (but NOT the banana
                // opener `(|` -- the `|`-excluded char class stops before it), so a
                // `polyglot NAME(entrypoint=@x)(| .. |)` head highlights the kwargs instead of
                // leaving `NAME(entrypoint=@x)` as bare text.
                // trailing lookahead: a DECLARATION is `keyword <one-name> [callform]`
                // immediately before a banana opener `(|`/`[|`/`{|` (body) or EOL (bodyless,
                // e.g. `container ubuntu`).  This REFUSES an INSTANTIATION head like
                // `container job hello(|`, where a 2nd bareword (`hello`) sits between the
                // keyword-name (`job`) and the banana -- that is a KIND+instance named-banana,
                // claimed by `cmk-banana-instance` below, not a declaration.
                pattern: /^[ \t]*(?:class|code|constructor|container|machine|dsl|factory|namespace|polyglot|protocol|strategy|mixin)\b[ \t]+[A-Za-z_][\w.+-]*(?:[ \t]*\([^()\r\n|]*\))?(?=[ \t]*(?:[([{]\||$))/m,
                inside: {
                    // `(?!\.)` after the boundary keeps the keyword from re-matching the
                    // leading segment of a DOTTED decl name (`constructor container.job` --
                    // the `container.` must stay part of the name, not become a 2nd keyword).
                    'cmk-decl-kw': { pattern: /^[ \t]*(?:class|code|constructor|container|machine|dsl|factory|namespace|polyglot|protocol|strategy|mixin)\b(?!\.)/, alias: 'keyword' },
                    // callform kwargs (`entrypoint=@render`) reuse the module-call shape: key ->
                    // attr-name, `=` -> operator, value -> attr-value.  BEFORE cmk-decl-name so
                    // it claims the whole pair (else the name rule grabs the bare value word).
                    'callform-kv': {
                        pattern: /[\w.+-]+=[^\s()]*/,
                        inside: {
                            'attr-name': /^[\w.+-]+/,
                            'operator': /=/,
                            'variable': /\$\{[^{}]*\}|\$+\w+/,
                            'attr-value': /[^\s()]+/,
                        },
                    },
                    'cmk-decl-name': { pattern: /[A-Za-z_][\w.+-]*/, alias: 'class-name' },
                    'punctuation': /[()]/,
                },
            },
            // module-level named-banana INSTANCE head: a KIND (one or more dotted words --
            // the space-form of a dotted constructor, `container job` = `container.job`)
            // followed by the instance NAME, then a banana opener -- e.g.
            // `container job hello(| .. |)`, `multistage image greeter(| .. |)`,
            // `jqlang git_status(| .. |)`.  The KIND words render as the type (class-name),
            // the final NAME as the callform (function).  Runs AFTER cmk-decl-head (so a
            // `constructor container.job[|` DECLARATION is claimed there first) and requires
            // 2+ words so a bare `portfolio(|` stays a plain cmk-banana-name below.  This is
            // what makes the keyword-led (`container ..`) and plain (`multistage ..`) instance
            // heads highlight IDENTICALLY instead of one misfiring as a declaration.
            'cmk-banana-instance': {
                pattern: /^[ \t]*[A-Za-z_][\w.+-]*(?:[ \t]+[A-Za-z_][\w.+-]*)+(?=[([{]\|)/m,
                inside: {
                    'cmk-banana-name': { pattern: /[A-Za-z_][\w.+-]*$/, alias: 'function' },
                    'cmk-decl-name': { pattern: /[A-Za-z_][\w.+-]*/, alias: 'class-name' },
                },
            },
            'cmk-banana-name': { pattern: /[\w+-][\w.+-]*(?=[([{]\|)/, alias: 'function' },
        });
  }
  root.registerCmkGrammar = registerCmkGrammar;
  // self-register when this file is loaded AFTER prism.js (Prism already global)
  if (root.Prism) { try { registerCmkGrammar(root.Prism); } catch (e) {} }
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this));
