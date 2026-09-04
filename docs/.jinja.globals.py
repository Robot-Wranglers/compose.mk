# compose.mk docs extension: cmk-notation -> native MathML / HTML.
# Loaded by the generic docs jinja driver's extension seam (DOCS_J2_GLOBALS or
# ${DOCS_ROOT}/.jinja.globals.py); exposes the `cmk_algebra` template global.
import json, re
from html import escape as _hesc
from latex2mathml.converter import convert
KW_OPEN, KW_CLOSE = chr(0xE000), chr(0xE001)
SYN_OPEN, SYN_CLOSE = chr(0xE002), chr(0xE003)
MONO_OPEN, MONO_CLOSE = chr(0xE004), chr(0xE005)
MV_OPEN, MV_CLOSE = chr(0xE00B), chr(0xE00C)
OP_OPEN, OP_CLOSE = chr(0xE00D), chr(0xE00E)
OP_CHARS, OP_TOKENS, SYN_CHARS = set("+*%!"), ("<-", "->", ":="), set("()|[]{}")
ARROW = r"\rightarrow"
_TOKEN = re.compile(r"@(\w+)|#(\w+)|`([^`]+)`")
_ARROW_GLYPH = {r"\rightarrow": "→"}
# < > & corrupt MathML markup and { } read as LaTeX grouping: swap to PUA sentinels
# before conversion, restore (entities / literal braces) in _post.
_ESC = {"&": chr(0xE008), "<": chr(0xE006), ">": chr(0xE007), "{": chr(0xE009), "}": chr(0xE00A)}
_UNESC = {chr(0xE008): "&amp;", chr(0xE006): "&lt;", chr(0xE007): "&gt;", chr(0xE009): "{", chr(0xE00A): "}"}
def _kind(ch):
    return "op" if ch in OP_CHARS else ("syn" if ch in SYN_CHARS else "plain")
def _segments(t):
    runs, i, n = [], 0, len(t)
    while i < n:
        tok = next((op for op in OP_TOKENS if t.startswith(op, i)), None)
        if tok:
            runs.append(("op", tok)); i += len(tok)
        else:
            runs.append((_kind(t[i]), t[i])); i += 1
    merged = []
    for k, s in runs:
        if merged and merged[-1][0] == k:
            merged[-1] = (k, merged[-1][1] + s)
        else:
            merged.append([k, s])
    return [(k, s) for k, s in merged]
def _esc(s):
    for k, v in _ESC.items():
        s = s.replace(k, v)
    return s
def _emit_text(t):
    _wrap = {"op": (OP_OPEN, OP_CLOSE), "syn": (SYN_OPEN, SYN_CLOSE)}
    parts = []
    for k, seg in _segments(t):
        if k in _wrap:
            o, c = _wrap[k]; parts.append(r"\text{" + o + _esc(seg) + c + "}")
        else:
            parts.append(r"\text{" + _esc(seg) + "}")
    return "".join(parts)
def cell_latex(spec):
    out, pos = [], 0
    for m in _TOKEN.finditer(spec):
        if m.start() > pos:
            out.append(_emit_text(spec[pos:m.start()]))
        var, kw, mono = m.group(1), m.group(2), m.group(3)
        if var is not None:
            out.append(r"\text{" + MV_OPEN + var + MV_CLOSE + "}")
        elif kw is not None:
            out.append(r"\text{" + KW_OPEN + _esc(kw) + KW_CLOSE + "}")
        else:
            out.append(r"\text{" + MONO_OPEN + _esc(mono) + MONO_CLOSE + "}")
        pos = m.end()
    if pos < len(spec):
        out.append(_emit_text(spec[pos:]))
    return "".join(out) or r"\text{}"
def _emit_text_html(t):
    _cls = {"op": "ca-op", "syn": "ca-syn"}
    return "".join(('<span class="' + _cls[k] + '">' + _hesc(seg) + "</span>") if k in _cls else _hesc(seg) for k, seg in _segments(t))
def cell_html(spec):
    out, pos = [], 0
    for m in _TOKEN.finditer(spec):
        if m.start() > pos:
            out.append(_emit_text_html(spec[pos:m.start()]))
        var, kw, mono = m.group(1), m.group(2), m.group(3)
        if var is not None:
            out.append('<i class="ca-mv">' + _hesc(var) + "</i>")
        elif kw is not None:
            out.append('<span class="ca-kw">' + _hesc(kw) + "</span>")
        else:
            out.append('<code class="ca-mono">' + _hesc(mono) + "</code>")
        pos = m.end()
    if pos < len(spec):
        out.append(_emit_text_html(spec[pos:]))
    return "".join(out)
def _post(mathml, *, block):
    for o, c, cls in ((KW_OPEN, KW_CLOSE, "kw"), (SYN_OPEN, SYN_CLOSE, "syn"), (OP_OPEN, OP_CLOSE, "op"), (MONO_OPEN, MONO_CLOSE, "mono")):
        mathml = re.sub(r"<mtext>" + o + r"(.*?)" + c + r"</mtext>", r'<mtext class="' + cls + r'">\1</mtext>', mathml)
    mathml = re.sub(r"<mtext>" + MV_OPEN + r"(.*?)" + MV_CLOSE + r"</mtext>", r'<mi>\1</mi>', mathml)
    for k, v in _UNESC.items():
        mathml = mathml.replace(k, v)
    mathml = mathml.replace(' mathvariant="italic"', '').replace(' mathvariant="sans-serif"', '')
    if block:
        mathml = mathml.replace('display="inline"', 'display="block"').replace("<mtable>", '<mtable columnspacing="0.6em" rowspacing="0.5em">')
    return mathml
def build_expr(expr, block):
    return _post(convert(cell_latex(expr)), block=block)
def build_block(rows, arrow=ARROW):
    arrow_html = '<span class="ca-arrow">' + _ARROW_GLYPH.get(arrow, arrow) + "</span>"
    entries = []
    for row in rows:
        lhs, rhs = row[0], row[1]
        defn = cell_html(rhs)
        if len(row) > 2 and row[2]:
            defn += '<div class="ca-example"><span class="ca-example-label">Example:</span> <code class="ca-mono">' + _hesc(row[2]) + "</code></div>"
        entries.append('<div class="ca-row"><dt class="ca-term">' + build_expr(lhs, block=False) + arrow_html + '</dt><dd class="ca-def">' + defn + "</dd></div>")
    return '<dl class="cmk-algebra-dl">' + "".join(entries) + "</dl>"
def _cmk_algebra(payload):
    spec = json.loads(payload) if isinstance(payload, str) else payload
    mode = spec.get("mode", "block")
    if mode == "inline":
        return build_expr(spec["expr"], block=False)
    if mode == "display":
        return build_expr(spec["expr"], block=True)
    return build_block(spec["rows"], arrow=spec.get("arrow", ARROW))

GLOBALS = {"cmk_algebra": _cmk_algebra}
