// Grammar regression tests for source.cmk.
//
// Loads the real cmk.tmLanguage.json with the exact engine VSCode uses
// (vscode-textmate + vscode-oniguruma) and asserts the scope assigned to
// specific spans of representative cmk source.  The embedded `source.shell`
// grammar is stubbed with a couple of recognizable rules so recipe-embedding
// can be asserted without pulling in the full shellscript grammar.
//
// Run:  npm test   (from via/vscode)

const fs = require('fs');
const path = require('path');
const vsctm = require('vscode-textmate');
const oniguruma = require('vscode-oniguruma');

const GRAMMAR = path.join(__dirname, '..', 'syntaxes', 'cmk.tmLanguage.json');

const onigLib = oniguruma
  .loadWASM(fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm')).buffer)
  .then(() => ({
    createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
    createOnigString: (s) => new oniguruma.OnigString(s),
  }));

const registry = new vsctm.Registry({
  onigLib,
  loadGrammar: async (scope) => {
    if (scope === 'source.cmk') {
      return vsctm.parseRawGrammar(fs.readFileSync(GRAMMAR, 'utf8'), GRAMMAR);
    }
    if (scope === 'source.shell') {
      return vsctm.parseRawGrammar(
        JSON.stringify({
          scopeName: 'source.shell',
          patterns: [
            { name: 'keyword.control.shell', match: '\\b(if|then|fi|for|do|done|while|case|esac|echo|printf|cat)\\b' },
            { name: 'string.quoted.double.shell', begin: '"', end: '"' },
          ],
        }),
        'shell.json'
      );
    }
    return null;
  },
});

// Each case: a single source line (or an array of lines tokenized as a block),
// a substring to locate, and the scope that substring's token must carry.
// `absent` asserts the substring's token does NOT carry the given scope.
const CASES = [
  // --- Phase 1: owned makefile base ---
  { line: 'NAME := value', find: 'NAME', scope: 'variable.other.readwrite.cmk' },
  { line: 'NAME := value', find: ':=', scope: 'keyword.operator.assignment.cmk' },
  { line: 'export FOO ?= bar', find: 'FOO', scope: 'variable.other.readwrite.cmk' },
  { line: '  indented.var += x', find: 'indented.var', scope: 'variable.other.readwrite.cmk' },
  { line: 'BUILT := $(shell uname -s)', find: 'shell', scope: 'support.function.builtin.cmk' },
  { line: 'files = $(wildcard *.c)', find: 'wildcard', scope: 'support.function.builtin.cmk' },
  { line: 'p := ${mk.def.read}/hello_world', find: 'hello_world', scope: 'entity.name.path.tail.cmk' },

  // --- recipe -> shell embedding (tab-anchored) ---
  { block: ['t:', '\t@echo "hi"'], line: 1, find: '@', scope: 'keyword.operator.recipe-prefix.cmk' },
  { block: ['t:', '\t@echo "hi"'], line: 1, find: 'echo', scope: 'keyword.control.shell' },
  { block: ['t:', '\tcp ${x}/f .'], line: 1, find: 'x', scope: 'variable.cmk' },

  // --- namespaced callform names (cmk-fxn) ---
  { line: '  log.target(doc=${d})', find: 'log.target', scope: 'entity.name.function.namespaced.cmk' },
  { line: '  cmk.log.io(x)', find: 'cmk.log.io', scope: 'entity.name.function.namespaced.cmk' },
  { line: '  io.foo/bar', find: 'io.foo', scope: 'entity.name.function.namespaced.cmk' },
  // a bare dotted word that is NOT a known namespace must stay unscoped
  { line: '  random.thing(x)', find: 'random.thing', scope: 'entity.name.function.namespaced.cmk', absent: true },

  // --- cmk constructs must still win (no regression) ---
  { line: 'x <- foo()', find: '<-', scope: 'keyword.operator.capture.cmk' },
  // handle bind `&NAME <- ..`: the `&` sigil + name scope distinctly (not shell `&`/plain text).
  { line: '&bound <- this.elixir/to_bind', find: '&', scope: 'keyword.operator.handle.cmk' },
  { line: '&bound <- this.elixir/to_bind', find: 'bound', scope: 'variable.other.handle.cmk' },
  { line: '&bound <- this.elixir/to_bind', find: '<-', scope: 'keyword.operator.capture.cmk' },
  // a YAML anchor (no trailing `<-`) must NOT be claimed as a handle.
  { line: '  alice: &base', find: '&', scope: 'keyword.operator.handle.cmk', absent: true },
  { line: 'body [| stuff |]', find: '[|', scope: 'keyword.operator.banana.cmk' },
  { line: 'target: dep1 dep2', find: 'target', scope: 'entity.name.function.target.cmk' },
  { line: 'target: dep1 dep2', find: 'dep1', scope: 'entity.name.function.target.prereq.cmk' },
  { line: "  ''' a docstring '''", find: 'docstring', scope: 'string.quoted.docstring.cmk' },
  { line: 'import io, flux', find: 'import', scope: 'keyword.control.import.cmk' },
  // `from <mod> import ...` -- Pythonic selective bind (from/import keywords + star + except).
  { line: 'from cmk import *', find: 'from', scope: 'keyword.control.import.from.cmk' },
  { line: 'from cmk import *', find: 'import', scope: 'keyword.control.import.cmk' },
  { line: 'from cmk import *', find: 'cmk', scope: 'entity.name.namespace.cmk' },
  { line: 'from dsl import jqlang, awklang', find: 'jqlang', scope: 'entity.name.namespace.cmk' },
  { line: 'from cmk import * except class container', find: 'except', scope: 'keyword.control.import.except.cmk' },
  { line: 'from cmk import * except class container', find: 'container', scope: 'entity.name.namespace.cmk' },
  // `open <mod> except ...` -- the except trailer highlights on the open form too.
  { line: 'open cmk except namespace', find: 'except', scope: 'keyword.control.import.except.cmk' },
  { line: 'open cmk except namespace', find: 'namespace', scope: 'entity.name.namespace.cmk' },

  // --- regression guards (non-shadowing: things that were colored before the owned base) ---
  // `export` modifier on an assignment keeps its keyword scope (not swallowed by the assign rule).
  { line: 'export FOO := x', find: 'export', scope: 'keyword.control.cmk' },
  { line: 'export FOO := x', find: 'FOO', scope: 'variable.other.readwrite.cmk' },
  // a `ns.name/%:` pattern-rule head stays a TARGET; the callform `/` lookahead must not grab it.
  { line: 'self.just.dispatch/%: dep', find: 'self.just.dispatch', scope: 'entity.name.function.target.cmk' },
  { line: 'self.just.dispatch/%: dep', find: 'self.just.dispatch', scope: 'entity.name.function.namespaced.cmk', absent: true },
  // recipe content keeps its cmk token scopes (the shell embed must not shadow strings/operators).
  { block: ['t:', '\techo "hi"'], line: 1, find: 'hi', scope: 'string.quoted.double.cmk' },
  { block: ['t:', '\ta | b'], line: 1, find: '|', scope: 'keyword.operator.shell.cmk' },
  { block: ['t:', '\texport V=1'], line: 1, find: 'export', scope: 'keyword.control.cmk' },

  // --- constructors / named bananas ---
  { line: 'strategy portfolio(| step |)', find: 'strategy', scope: 'storage.type.cmk' },
  { line: 'strategy portfolio(| step |)', find: 'portfolio', scope: 'entity.name.type.cmk' },
  { line: 'constructor jqlang(| ${self} |)', find: 'constructor', scope: 'storage.type.cmk' },
  { line: 'class Cook[| body |]', find: 'Cook', scope: 'entity.name.type.cmk' },
  { line: 'container ubuntu', find: 'container', scope: 'storage.type.cmk' },
  { line: 'container ubuntu', find: 'ubuntu', scope: 'entity.name.type.cmk' },
  // bare named banana + user-KIND head: the name before the banana opener is scoped.
  { line: 'portfolio(| bare |)', find: 'portfolio', scope: 'entity.name.function.cmk' },
  { line: 'jqlang git_status(| q |)', find: 'git_status', scope: 'entity.name.function.cmk' },
  // guard: banana-name must stop the greedy target rule from swallowing `X(| .. : .. |)`.
  { line: 'component(| $(1).build:; echo hi |)', find: 'component', scope: 'entity.name.function.cmk' },
  { line: 'component(| $(1).build:; echo hi |)', find: 'component', scope: 'entity.name.function.target.cmk', absent: true },
  // guard: a KIND-prefixed named-banana head with a `:` in the body (jq object) must NOT be
  // mis-read as a target -- the name is off column 0, so the target-rule lookahead (not
  // banana-name) is what refuses it.
  { line: 'jqlang wrap(|   { result: . } |)', find: 'wrap', scope: 'entity.name.function.cmk' },
  { line: 'jqlang wrap(|   { result: . } |)', find: 'jqlang wrap(|   { result', scope: 'entity.name.function.target.cmk', absent: true },
  { line: 'jqlang wrap(|   { result: . } |)', find: 'jqlang', scope: 'entity.name.function.target.cmk', absent: true },
  // --- named-banana INSTANCE heads (KIND words + instance name), #banana-instance ---
  // keyword-led KIND (`container job` = the space-form of ctor `container.job`): the KIND
  // words are the type, the final word is the callform -- and `container` must NOT stay a
  // decl keyword (would mean the line was mis-claimed as a declaration).
  { line: 'container job hello(| FROM alpine |)', find: 'hello', scope: 'entity.name.function.cmk' },
  { line: 'container job hello(| FROM alpine |)', find: 'container', scope: 'entity.name.type.cmk' },
  { line: 'container job hello(| FROM alpine |)', find: 'container', scope: 'storage.type.cmk', absent: true },
  // plain (non-keyword) KIND scopes IDENTICALLY -- this consistency is the point of the fix.
  { line: 'multistage image greeter(| FROM alpine |)', find: 'greeter', scope: 'entity.name.function.cmk' },
  { line: 'multistage image greeter(| FROM alpine |)', find: 'image', scope: 'entity.name.type.cmk' },
  // a DOTTED constructor name is captured WHOLE (not split at the `.`), and the 2+-word
  // instance rule must not steal a single-name `constructor NAME[|` declaration.
  { line: 'constructor multistage.image[| body |]', find: 'constructor', scope: 'storage.type.cmk' },
  { line: 'constructor multistage.image[| body |]', find: 'multistage.image', scope: 'entity.name.type.cmk' },

  // --- ░ (U+2591) light-shade support: the divider run and stray shade glyphs go bright red ---
  // in a `##░░░` divider, the ░ run takes the dedicated shade scope while the `#` prefix stays a divider comment.
  { line: '##░░░░░░ Section ░░░░', find: '░░░░░░', scope: 'constant.character.shade.cmk' },
  { line: '##░░░░░░ Section ░░░░', find: '##', scope: 'comment.line.divider.cmk' },
  // a bare ░ outside any divider (e.g. figlet-style banner art) still takes the shade scope.
  { line: '░██  ░██ ██░░░░██', find: '░██', scope: 'constant.character.shade.cmk' },

  // --- docker-compose keys, wherever they appear (#compose-key) ---
  // inlined compose yaml -- the key is scoped, the value is not.
  { line: '    image: alpine:3.19', find: 'image', scope: 'keyword.other.compose.cmk' },
  { line: '    working_dir: /workspace', find: 'working_dir', scope: 'keyword.other.compose.cmk' },
  { line: '    entrypoint: ["/bin/sh"]', find: 'entrypoint', scope: 'keyword.other.compose.cmk' },
  { line: '    volumes:', find: 'volumes', scope: 'keyword.other.compose.cmk' },
  { line: '    image: alpine:3.19', find: 'alpine', scope: 'keyword.other.compose.cmk', absent: true },
  // a longer key must win over its own prefix (`dns` must not eat `dns_search`).
  { line: '    dns_search: example.com', find: 'dns_search', scope: 'keyword.other.compose.cmk' },
  // callform kwargs, on a decl head and on an import directive alike.
  { line: 'container job hello(image=alpine)(| FROM alpine |)', find: 'image', scope: 'keyword.other.compose.cmk' },
  { line: '@args.from_json(shape working_dir=/tmp)', find: 'working_dir', scope: 'keyword.other.compose.cmk' },
  { line: 'import ./demos/foo.cmk as foo image=debian', find: 'image', scope: 'keyword.other.compose.cmk' },
  // recipe body (the shell embed must not shadow the key).
  { block: ['t:', '\tcompose.run image=alpine'], line: 1, find: 'image', scope: 'keyword.other.compose.cmk' },
  // a column-0 makefile rule head keeps its target scope -- `build:` is a target, not a key.
  { line: 'build: dep', find: 'build', scope: 'entity.name.function.target.cmk' },
  { line: 'build: dep', find: 'build', scope: 'keyword.other.compose.cmk', absent: true },
  // a compose word with no trailing `:`/`=` is left alone.
  { line: 'multistage image greeter(| FROM alpine |)', find: 'image', scope: 'keyword.other.compose.cmk', absent: true },
  // the value side scopes separately (rendered a shade larger in the docs, brighter in vscode).
  { line: '    image: alpine:3.19', find: 'alpine:3.19', scope: 'meta.value.compose.cmk' },
  { line: '    image: alpine:3.19', find: ':', scope: 'punctuation.separator.key-value.compose.cmk' },
  { line: '    command: sh -c hello', find: 'sh -c hello', scope: 'meta.value.compose.cmk' },
  // a value stops at a sibling kwarg, and at a banana closer.
  { line: 'container job hello(image=alpine entrypoint=sh)', find: 'entrypoint', scope: 'keyword.other.compose.cmk' },
  { line: 'container job hello(| image=alpine entrypoint=sh |)', find: '|)', scope: 'meta.value.compose.cmk', absent: true },
];

function tokenScopesAt(grammar, lines, lineIdx, substr) {
  let stack = vsctm.INITIAL;
  let res = null;
  for (let i = 0; i <= lineIdx; i++) {
    res = grammar.tokenizeLine(lines[i], stack);
    stack = res.ruleStack;
  }
  const line = lines[lineIdx];
  const start = line.indexOf(substr);
  if (start < 0) return { error: `substring ${JSON.stringify(substr)} not found` };
  // find the token covering the start of the substring
  const tok = res.tokens.find((t) => t.startIndex <= start && start < t.endIndex);
  return { scopes: tok ? tok.scopes : [] };
}

registry.loadGrammar('source.cmk').then((grammar) => {
  let pass = 0;
  const failures = [];
  for (const c of CASES) {
    const lines = c.block || [c.line];
    const idx = c.block ? c.line : 0;
    const r = tokenScopesAt(grammar, lines, idx, c.find);
    const label = `${JSON.stringify((c.block || [c.line])[idx])} @ ${JSON.stringify(c.find)} -> ${c.scope}${c.absent ? ' (absent)' : ''}`;
    if (r.error) { failures.push(`${label}: ${r.error}`); continue; }
    const has = r.scopes.includes(c.scope);
    if (c.absent ? !has : has) { pass++; }
    else { failures.push(`${label}: got [${r.scopes.filter((s) => s !== 'source.cmk').join(', ')}]`); }
  }
  console.log(`grammar tests: ${pass}/${CASES.length} passed`);
  if (failures.length) {
    console.error('\nFAILURES:');
    for (const f of failures) console.error('  ✗ ' + f);
    process.exit(1);
  }
}).catch((e) => { console.error(e); process.exit(1); });
