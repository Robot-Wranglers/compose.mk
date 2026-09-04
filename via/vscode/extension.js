// compose.mk / cmk-lang VSCode extension -- runtime entry point.
//
// Adds a shebang-aware "run" CodeLens above every runnable target in a
// .cmk file, replacing the generic Makefile run button with something that
// actually respects how a cmk script is meant to be launched (its shebang).
//
// Behavior:
//   * A "$(play) run" lens is placed above each target definition.
//   * If a doc-block (contiguous `#` comment lines) sits directly above the
//     target, the lens is anchored ABOVE the doc-block so it never wedges
//     itself between the docs and the target they describe.
//   * Running a target executes the file's shebang (`#!...`) with the target
//     appended, so E `#!/usr/bin/env -S ./compose.mk cmk run` Just Works.
//   * If the file has no shebang, we REFUSE to run and say why -- a cmk
//     script without a `#!` line has no defined way to launch.

const vscode = require('vscode');
const fs = require('fs');
const path = require('path');

// A target definition at column 0.  The first char is a letter/underscore
// (so GNU special targets like `.PHONY` and leading-`%` patterns are skipped),
// and the name carries no space/`:`/`=`/`#`/`%` (so `%`-pattern targets, which
// cannot be run literally, are skipped too).  The name is followed by `:` or
// `::` that is not part of an assignment operator.
const TARGET_RE = /^([A-Za-z_][^\s:=#%]*)\s*::?(?!=)/;

// Guard: a variable assignment can masquerade as a target head
// (`x := y`, `x ::= y`, `x ?= y`, ...).  Skip those outright.
const ASSIGN_RE = /^[^\s:#]*\s*(?:::=|:=|\?=|\+=|!=|=)/;

const isComment = (text) => /^\s*#/.test(text);
const isShebang = (text) => /^#!/.test(text);

class CmkRunnerProvider {
  constructor() {
    this._emitter = new vscode.EventEmitter();
    this.onDidChangeCodeLenses = this._emitter.event;
  }

  refresh() {
    this._emitter.fire();
  }

  provideCodeLenses(document) {
    if (!vscode.workspace.getConfiguration('cmk').get('showRunButton', true)) {
      return [];
    }
    const lenses = [];
    for (let i = 0; i < document.lineCount; i++) {
      const text = document.lineAt(i).text;
      if (ASSIGN_RE.test(text)) continue;
      const m = TARGET_RE.exec(text);
      if (!m) continue;
      const target = m[1];

      // Walk up over a doc-block (contiguous comment lines, no blank gap)
      // that sits directly above the target, and anchor the lens at its top
      // so the runner appears ABOVE the docs rather than interrupting them.
      let anchor = i;
      for (let j = i - 1; j >= 0; j--) {
        const above = document.lineAt(j).text;
        if (isShebang(above)) break;   // never anchor onto the shebang line
        if (!isComment(above)) break;  // a blank line or code ends the block
        anchor = j;
      }

      const range = new vscode.Range(anchor, 0, anchor, 0);
      lenses.push(new vscode.CodeLens(range, {
        title: '$(play) run',
        tooltip: `Run the '${target}' target (via this file's shebang)`,
        command: 'cmk.runTarget',
        arguments: [document.uri, target],
      }));
    }
    return lenses;
  }
}

// Read the first line of a file, preferring the live editor buffer (so an
// unsaved shebang edit is honored) and falling back to disk.
function firstLineOf(uri) {
  const open = vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
  if (open) return open.lineCount ? open.lineAt(0).text : '';
  try {
    return (fs.readFileSync(uri.fsPath, 'utf8').split(/\r?\n/, 1)[0]) || '';
  } catch (_) {
    return '';
  }
}

// POSIX single-quote a shell argument.
const shq = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

let sharedTerminal = null;
let sharedCwd = null;

function terminalFor(cwd) {
  if (sharedTerminal && sharedTerminal.exitStatus === undefined && sharedCwd === cwd) {
    return sharedTerminal;
  }
  if (sharedTerminal) {
    try { sharedTerminal.dispose(); } catch (_) { /* already gone */ }
  }
  sharedTerminal = vscode.window.createTerminal({ name: 'cmk run', cwd });
  sharedCwd = cwd;
  return sharedTerminal;
}

function runTarget(uri, target) {
  const first = firstLineOf(uri);
  if (!isShebang(first)) {
    vscode.window.showErrorMessage(
      `cmk: refusing to run '${target}' -- ${path.basename(uri.fsPath)} has no shebang. ` +
      `Add a '#!' line (e.g. '#!/usr/bin/env -S ./compose.mk cmk run') to make it runnable.`);
    return;
  }
  const interp = first.replace(/^#!\s*/, '').trim();
  if (!interp) {
    vscode.window.showErrorMessage(`cmk: refusing to run '${target}' -- the shebang is empty.`);
    return;
  }

  // Run from the workspace folder that owns the file, so a relative
  // interpreter in the shebang (e.g. `./compose.mk`) resolves.
  const folder = vscode.workspace.getWorkspaceFolder(uri);
  const cwd = folder ? folder.uri.fsPath : path.dirname(uri.fsPath);
  const fileArg = folder ? path.relative(cwd, uri.fsPath) : uri.fsPath;

  // The shebang tells the kernel how to launch this file; we replay exactly
  // that, with the file and target appended.  `env -S` splitting is idempotent
  // over the shell's own tokenization, so this matches `./<file> <target>`.
  const cmd = `${interp} ${shq(fileArg)} ${shq(target)}`;

  const term = terminalFor(cwd);
  term.show(true);
  term.sendText(cmd, true);
}

// =====================================================================
// Emphasis decorations -- the "more than theming" layer.
//
// TextMate/semantic theming only gives color + bold/italic/underline, and the
// editor has NO per-token font-size.  Decorations (applied imperatively over
// computed ranges) unlock the rest: letter-spacing, boxes/outlines, sized
// pseudo-element markers, and -- as an explicit opt-in -- the unsupported
// `textDecoration` font-size hack.  `cmk.emphasis.style` picks the mechanism so
// each can be exercised and compared; it is applied to the banana-block
// delimiters `(| |)` and top-level target names (the elements we most wanted
// "bigger" but cannot enlarge through the grammar).
// =====================================================================

const BANANA_RE = /\(\||\|\)/g;

// One active decoration type, rebuilt when the style/scale setting changes.
// Disposing it also clears its decorations from every editor, so the previous
// style leaves no residue when switching.
let decoType = null;
let decoKey = null;

function emphasisConfig() {
  const cfg = vscode.workspace.getConfiguration('cmk');
  return {
    style: cfg.get('emphasis.style', 'bold'),
    scale: cfg.get('emphasis.fontSizeScale', 1.6),
    fontFamily: cfg.get('emphasis.fontFamily', '"Georgia", "Iowan Old Style", "Times New Roman", serif'),
  };
}

// Sanitize a user font-family before it goes into the injected CSS string:
// strip anything that could break out of the `font-family: ...;` declaration.
function safeFontFamily(family) {
  const f = String(family || '').replace(/[;{}]/g, '').trim();
  return f;
}

// Build the decoration type for a given style.  Each `case` is one of the
// mechanisms discussed; `fontSize` is the ONLY unsupported one.
function buildDecorationType(style, scale, fontFamily) {
  switch (style) {
    case 'off':
      return null;

    // Supported, zero layout risk: just heavier weight.
    case 'bold':
      return vscode.window.createTextEditorDecorationType({ fontWeight: 'bold' });

    // Supported: bold + wider tracking, so the token physically occupies more
    // horizontal space without touching line height.
    case 'spacing':
      return vscode.window.createTextEditorDecorationType({
        fontWeight: 'bold',
        letterSpacing: '0.18em',
      });

    // Supported: a sized colored block prepended as a `before` attachment
    // (attachments honor width/height, so this is a genuinely bigger glyph that
    // lives ALONGSIDE the token rather than resizing it -- no layout breakage).
    case 'marker':
      return vscode.window.createTextEditorDecorationType({
        fontWeight: 'bold',
        before: {
          contentText: ' ',
          width: '0.32em',
          height: '1.1em',
          margin: '0 3px -0.15em 0',
          backgroundColor: new vscode.ThemeColor('textLink.foreground'),
        },
      });

    // Supported: bold + a rounded outline, enlarging the token's visual
    // footprint via a box (border color follows the theme).
    case 'box':
      return vscode.window.createTextEditorDecorationType({
        fontWeight: 'bold',
        border: '1px solid',
        borderColor: new vscode.ThemeColor('focusBorder'),
        borderRadius: '3px',
      });

    // UNSUPPORTED opt-in: the FULL CSS-injection hack -- bigger (`font-size`),
    // bolder (`font-weight: 900`), and a different `font-family` all ride the
    // `textDecoration` field, because the structured decoration API exposes none
    // of them.  Line height does NOT reflow, so large scales clip the line above
    // and skew cursor/selection geometry.
    // GRACEFUL DEGRADATION: bold + letterSpacing are set as REAL supported props
    // too, so if a VSCode build ignores/strips the injected CSS the emphasis
    // falls back to bold+spacing (size/weight/family just revert to the editor
    // defaults) instead of vanishing.
    case 'fontSize': {
      const size = Math.max(1, Math.min(2.5, Number(scale) || 1.6));
      const family = safeFontFamily(fontFamily);
      return vscode.window.createTextEditorDecorationType({
        fontWeight: 'bold',
        letterSpacing: '0.08em',
        textDecoration:
          `none; font-size: ${size}em; font-weight: 900;` +
          (family ? ` font-family: ${family};` : '') +
          ` display: inline-block; line-height: 1;`,
      });
    }

    default:
      return null;
  }
}

// (Re)build the active decoration type iff the style/scale changed.  Disposing
// the old type first clears its decorations everywhere (clean style switch).
function ensureDecoType() {
  const { style, scale, fontFamily } = emphasisConfig();
  const key = `${style}:${scale}:${fontFamily}`;
  if (key === decoKey) return decoType;
  if (decoType) { try { decoType.dispose(); } catch (_) { /* gone */ } decoType = null; }
  decoType = buildDecorationType(style, scale, fontFamily);
  decoKey = key;
  return decoType;
}

// Ranges to emphasize in a cmk document: every `(|`/`|)` banana delimiter, plus
// each top-level target NAME (reusing the CodeLens matchers).
function emphasisRanges(document) {
  const ranges = [];
  for (let i = 0; i < document.lineCount; i++) {
    const line = document.lineAt(i).text;
    if (isComment(line)) continue;   // don't decorate `(|`-lookalikes in prose
    BANANA_RE.lastIndex = 0;
    let m;
    while ((m = BANANA_RE.exec(line)) !== null) {
      ranges.push(new vscode.Range(i, m.index, i, m.index + m[0].length));
    }
    if (!ASSIGN_RE.test(line)) {
      const t = TARGET_RE.exec(line);
      if (t) ranges.push(new vscode.Range(i, 0, i, t[1].length));
    }
  }
  return ranges;
}

function applyEmphasis(editor) {
  if (!editor || editor.document.languageId !== 'cmk') return;
  const dt = ensureDecoType();
  if (!dt) return;   // style 'off' -- ensureDecoType already cleared any prior type
  editor.setDecorations(dt, emphasisRanges(editor.document));
}

function applyEmphasisAll() {
  ensureDecoType();
  for (const ed of vscode.window.visibleTextEditors) applyEmphasis(ed);
}

function activate(context) {
  const provider = new CmkRunnerProvider();

  // Debounce re-decoration on edits (per document).
  const decoTimers = new Map();
  const scheduleEmphasis = (document) => {
    const key = document.uri.toString();
    clearTimeout(decoTimers.get(key));
    decoTimers.set(key, setTimeout(() => {
      decoTimers.delete(key);
      const ed = vscode.window.visibleTextEditors.find((e) => e.document === document);
      if (ed) applyEmphasis(ed);
    }, 150));
  };

  context.subscriptions.push(
    vscode.languages.registerCodeLensProvider({ language: 'cmk' }, provider),
    vscode.commands.registerCommand('cmk.runTarget', runTarget),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('cmk.showRunButton')) provider.refresh();
      if (e.affectsConfiguration('cmk.emphasis')) applyEmphasisAll();
    }),
    vscode.window.onDidChangeActiveTextEditor((ed) => applyEmphasis(ed)),
    vscode.window.onDidChangeVisibleTextEditors(() => applyEmphasisAll()),
    vscode.workspace.onDidChangeTextDocument((e) => scheduleEmphasis(e.document)),
    vscode.window.onDidCloseTerminal((t) => {
      if (t === sharedTerminal) { sharedTerminal = null; sharedCwd = null; }
    }),
    { dispose: () => { if (decoType) { try { decoType.dispose(); } catch (_) {} decoType = null; } } }
  );

  applyEmphasisAll();   // decorate whatever is already open
}

function deactivate() {}

module.exports = { activate, deactivate };
