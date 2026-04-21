/*
 * Assign 'docutils' class to tables so styling and
 * JavaScript behavior is applied.  `.quickref` tables opt out -- they carry
 * their own compact/zebra styling (see css/compose.mk.css).
 *
 * https://github.com/mkdocs/mkdocs/issues/2028
 */

$('div.rst-content table:not(.quickref)').addClass('docutils');
document.addEventListener('DOMContentLoaded', function() {
    // Wait for MkDocs to fully render the page including ToC
    setTimeout(function() {

        // The cmk/makefile Prism grammar now lives in js/prism-cmk.js (loaded first).
        // Register it here (idempotent) so the authoritative re-highlight below sees it.
        if (typeof registerCmkGrammar === 'function') { registerCmkGrammar(Prism); }
        // Grammar-race fix + authoritative highlight pass.  Pygments is now OFF
        // (mkdocs.yml `pymdownx.highlight: use_pygments:false`), so every fenced block
        // renders server-side as a RAW `<pre class="highlight"><code class="language-<x>">`
        // with no token spans -- Prism is the sole highlighter.  Two things still need
        // this pass: (1) RACE -- theme_base.js runs its own highlight in an earlier
        // DOMContentLoaded setTimeout, BEFORE the cmk grammar is registered (just above,
        // via prism-cmk.js), so that first paint lacks the cmk tokens; (2) idempotence -- re-clearing
        // to plain text then highlighting once guarantees a single, grammar-complete pass.
        // `.nohighlight` blocks (e.g. the api_docs help dumps) are left verbatim.
        document.querySelectorAll('code[class*="language-"]').forEach(el => {
            if (el.classList.contains('nohighlight')) return;
            el.textContent = el.textContent;
            Prism.highlightElement(el);
        });

        const wrapTextNodeWithSpan = (text, classes) => {
            const span = document.createElement('span');
            span.textContent = text.nodeValue; 
            span.className = classes;
            text.parentNode.replaceChild(span, text); return span; 
        };
        document.querySelectorAll('div.highlight:not(.nohighlight) code').forEach(
            node => {
            const textNodes = Array
                .from(node.childNodes)
                .filter(node => node.nodeType === Node.TEXT_NODE);
            textNodes.forEach(text=> {
                if (text.nodeValue.search(/(?:(log|flux))(?:[.])(?:[,])\b/)!=-1){
                    wrapTextNodeWithSpan(text, "token cmk-fxn")
                }
                else if (text.nodeValue.search(/(?<![A-Za-z0-9_.\&])(cat|find|rm|ls|[.]\/compose[.]mk)(?![A-Za-z0-9_.])/)!=-1){
                    wrapTextNodeWithSpan(text, "token nb")
                }
                else { 
                    //console.log("unrecognized:",text.nodeValue);
                }
            })
        });

        // CMK-lang special glyphs that carry no syntax-highlight token of their own
        // (ᐉ 🡄 🡆 ⬦ ⬥ ⨖): wrap each occurrence with the `si` special-glyph class
        // group -- identical to the `line_feed` token's alias (`si punctuation cmk-syntax`).
        // Done as a post-highlight DOM pass because the custom cmk grammar is registered
        // AFTER theme_base.js highlights, so those grammar tokens never apply to the embeds
        // here.  Splits the text node so only the glyph is styled; idempotent (skips a glyph
        // already inside an `si` span).
        const CMK_GLYPHS = /(ᐉ|🡄|🡆|⬦|⬥|⨖)/u;
        document.querySelectorAll(
            'div.highlight code, div.snippet code, .cli_example, code[class*="language-"]'
        ).forEach(root => {
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
            const hits = [];
            for (let t; (t = walker.nextNode());) {
                if (CMK_GLYPHS.test(t.nodeValue) &&
                    !(t.parentNode.classList && t.parentNode.classList.contains('si'))) {
                    hits.push(t);
                }
            }
            hits.forEach(t => {
                const frag = document.createDocumentFragment();
                t.nodeValue.split(CMK_GLYPHS).forEach((part, i) => {
                    if (part === '') return;
                    if (i % 2 === 1) {
                        const s = document.createElement('span');
                        s.className = 'token si punctuation cmk-syntax';
                        s.textContent = part;
                        frag.appendChild(s);
                    } else {
                        frag.appendChild(document.createTextNode(part));
                    }
                });
                t.parentNode.replaceChild(frag, t);
            });
        });

        // File-header demo names: a leading `# <name>.cmk:` / `# <name>.mk:` comment (e.g.
        // `# blockrefs.cmk:`) -- color just the filename yellow.  Post-highlight DOM pass
        // (custom grammar tokens don't apply to the embeds; cf. the glyph pass above).
        // Anchored at `^#\s+<name>.<ext>` immediately before a `:`, so description lines and
        // in-text mentions are left alone.  Splits the text node so only the name is styled;
        // idempotent (skips a name already wrapped).
        const DEMO_HDR = /^(#\s+)([\w.+-]+\.(?:cmk|mk))(?=:)/;
        document.querySelectorAll(
            'div.highlight code, div.snippet code, .cli_example, code[class*="language-"]'
        ).forEach(root => {
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
            const hits = [];
            for (let t; (t = walker.nextNode());) {
                const m = t.nodeValue.match(DEMO_HDR);
                if (m && !(t.parentNode.classList && t.parentNode.classList.contains('cmk-demo-name'))) {
                    hits.push([t, m]);
                }
            }
            hits.forEach(([t, m]) => {
                const frag = document.createDocumentFragment();
                frag.appendChild(document.createTextNode(m[1]));
                const s = document.createElement('span');
                s.className = 'cmk-demo-name';
                s.textContent = m[2];
                frag.appendChild(s);
                frag.appendChild(document.createTextNode(t.nodeValue.slice(m[0].length)));
                t.parentNode.replaceChild(frag, t);
            });
        });

        // (Define-body highlighting is now grammar-driven -- see the `define-block`
        //  token above.  The old, buggy `span.keyword-define` DOM walk was removed.)

        // Color CONSTANTS: a var-ref whose NAME describes an ANSI color/style (e.g.
        // `${green}`, `${dim_cyan}`, `${bold_red}`) is rendered IN that color -- a FIXED,
        // theme-independent map, because a color's meaning ("green") is the same in every
        // palette (this is the one place a fixed hue is correct).  Post-highlight DOM pass
        // over the `.token.var-name` spans; inline styles win over the theme.  Names split
        // on `_`/`.`; `dim_`/`bold_`/`underline_` modifiers stack; unknown names untouched.
        const CMK_COLORS = { black: '#666', red: '#e06c75', green: '#98c379',
            yellow: '#e5c07b', blue: '#61afef', magenta: '#c678dd', purple: '#c678dd',
            cyan: '#56b6c2', white: '#e6e6e6', orange: '#e0a458', grey: '#aaa', gray: '#aaa' };
        document.querySelectorAll('.token.var-name').forEach(el => {
            let color = null, bold = false, dim = false, underline = false;
            el.textContent.toLowerCase().split(/[_.]/).forEach(p => {
                if (Object.prototype.hasOwnProperty.call(CMK_COLORS, p)) color = CMK_COLORS[p];
                else if (p === 'bold') bold = true;
                else if (p === 'dim' || p === 'faint') dim = true;
                else if (p === 'underline' || p === 'ul') underline = true;
            });
            if (!color && !bold && !dim && !underline) return;
            if (color) el.style.color = color;
            if (bold) el.style.fontWeight = 'bold';
            if (dim) el.style.opacity = '0.6';
            if (underline) el.style.textDecoration = 'underline';
        });

    }, 100); // Small delay to ensure ToC is already processed
    })


/* (wrapContiguousDefineBlocks / wrapNodesInDefineBlock removed -- they wrapped the
 * old DOM-walk's `inside_define` spans, which the grammar-driven `define-block` token
 * now supersedes.  Neither was ever called.) */

/*
 * Image lightbox.  The `img_link` macro wraps each <img> in an
 * <a href="<the image>">, so clicking would normally navigate to the raw file.
 * Instead we show it enlarged in a modal overlay.  Close with the Escape key or
 * by clicking anywhere outside the image.  Only anchors whose href is an image
 * file are intercepted, so `img_link(... link=<page>)` (non-image targets) still
 * navigate normally.  Styling: `#img-modal` in css/compose.mk.css.
 */
document.addEventListener('DOMContentLoaded', function () {
  function isImageHref(href) {
    return href && /\.(?:png|gif|jpe?g|svg|webp)(?:[?#].*)?$/i.test(href);
  }
  var modal = document.createElement('div');
  modal.id = 'img-modal';
  var big = document.createElement('img');
  var caption = document.createElement('div');
  caption.id = 'img-modal-caption';
  modal.appendChild(big);
  modal.appendChild(caption);
  document.body.appendChild(modal);

  // the trailing image filename from an href, URL-decoded (".../img/docker.png" -> "docker.png")
  function fileNameFromHref(href) {
    var path = href.split(/[?#]/)[0].replace(/\/+$/, '');
    var base = path.substring(path.lastIndexOf('/') + 1);
    try { base = decodeURIComponent(base); } catch (e) { /* keep raw */ }
    return base;
  }

  function close() {
    modal.classList.remove('open');
    big.removeAttribute('src');
    caption.textContent = '';
  }

  // open: click on an anchor that wraps an <img> and points at an image file
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a');
    if (!a || !a.querySelector('img') || !isImageHref(a.getAttribute('href'))) {
      return;
    }
    e.preventDefault();
    big.src = a.href;
    caption.textContent = fileNameFromHref(a.getAttribute('href'));
    modal.classList.add('open');
  });

  // close: click on the backdrop (i.e. anywhere but the image itself)
  modal.addEventListener('click', function (e) {
    if (e.target !== big) { close(); }
  });
  // close: Escape key
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { close(); }
  });
});


/*
 * Give every content table a stable, unique id so they're easy to refer to.
 * The id is derived from the nearest preceding heading (a table under the
 * "Families" heading -> id "families-table"), numbered when a heading has more
 * than one table, with a final de-dup guard.  Tables that already carry an id
 * are left alone.
 */
document.addEventListener('DOMContentLoaded', function () {
  var content = document.querySelector('.rst-content') || document.body;
  var nodes = content.querySelectorAll(
    'h1[id], h2[id], h3[id], h4[id], h5[id], h6[id], table'
  );
  var lastHeading = '';
  var counts = {};
  nodes.forEach(function (n) {
    if (n.tagName !== 'TABLE') {
      if (n.id) { lastHeading = n.id; }
      return;
    }
    if (n.id) { return; }
    var base = lastHeading ? lastHeading + '-table' : 'table';
    counts[base] = (counts[base] || 0) + 1;
    var id = counts[base] > 1 ? base + '-' + counts[base] : base;
    while (document.getElementById(id)) { id += 'x'; }
    n.id = id;
  });

  /* Smarter word-wrap for the families table's macro chips: insert a <wbr> break
   * opportunity after each dot, so a long dotted name (e.g. compose.import.string)
   * reflows at its dots instead of overflowing the column.  Chips are plain-text
   * <code>, so rebuild from textContent (no existing markup to clobber). */
  content.querySelectorAll('td.macro-list code').forEach(function (c) {
    if (c.textContent.indexOf('.') !== -1) {
      c.innerHTML = c.textContent.replace(/\./g, '.<wbr>');
    }
  });
});


/*
 * Sidebar nav code-path annotations.  A parenthetical in a nav title (e.g.
 * "Typed Exceptions (fault.*)") is wrapped in a <span class="nav-annot"> so ALL
 * styling stays in CSS (`.nav-annot` in compose.mk.css renders it small / italic /
 * monospace / bold).  Cheap: one scoped query, a `textContent.indexOf('(')` fast-
 * skip so the majority of links (no parenthetical) are never touched, and only the
 * few annotated titles get a minimal node rewrite.  Idempotent -- once wrapped, the
 * parenthetical lives in the span, not a text node, so a re-run is a no-op.
 */
document.addEventListener('DOMContentLoaded', function () {
  var links = document.querySelectorAll('.wy-menu-vertical a');
  for (var i = 0; i < links.length; i++) {
    var a = links[i];
    if (a.textContent.indexOf('(') === -1) continue;      // fast skip (no parenthetical)
    for (var n = a.firstChild; n; n = n.nextSibling) {
      if (n.nodeType !== 3) continue;                     // text nodes only (skip toggles)
      var m = n.nodeValue.match(/^(.*?)(\([^()]+\))(.*)$/);
      if (!m) continue;
      var span = document.createElement('span');
      span.className = 'nav-annot';
      span.textContent = m[2];
      n.nodeValue = m[1];                                 // keep "before" in the text node
      a.insertBefore(span, n.nextSibling);
      if (m[3]) a.insertBefore(document.createTextNode(m[3]), span.nextSibling);
      break;                                              // one parenthetical per title
    }
  }
});

/*
 * Header permalinks.  Make every id'd heading click-to-permalink: a click updates the
 * URL hash (so the address bar shows the permalink) and copies the full URL to the
 * clipboard.  No <a> wrapper, so there's no underline -- just a pointer cursor (set in
 * compose.mk.css) as the affordance.  Clicks on a real link inside a heading pass through.
 */
document.addEventListener('DOMContentLoaded', function () {
  var content = document.querySelector('.rst-content') || document.body;
  content.querySelectorAll('h1[id],h2[id],h3[id],h4[id],h5[id],h6[id]').forEach(function (h) {
    h.title = 'Click to copy a permalink to this section';
    h.addEventListener('click', function (e) {
      if (e.target.closest('a')) { return; }            // don't hijack real links
      history.replaceState(null, '', '#' + h.id);        // permalink in the address bar (no jump)
      var url = location.origin + location.pathname + '#' + h.id;
      if (navigator.clipboard) { navigator.clipboard.writeText(url).catch(function () {}); }
      h.classList.add('permalinked');                    // brief visual ack (css fades it)
      setTimeout(function () { h.classList.remove('permalinked'); }, 900);
    });
  });
});

/*
 * cli_example copy button.  Park an unobtrusive Tabler clipboard glyph at the top-right of
 * every `pre.highlight > code.cli_example` block (revealed on hover, styled in compose.mk.css).
 * A click copies the CLI SEGMENT with the shell prompt removed: every `$`-prefixed line is
 * kept (prompt stripped) along with its `\`-continuations, and inline OUTPUT lines are dropped,
 * so the copy pastes straight into a shell.  Ack: swap to a check glyph + `.copied` for ~1.2s.
 */
document.addEventListener('DOMContentLoaded', function () {
  var CLIP = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M9 5h-2a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-12a2 2 0 0 0 -2 -2h-2" /><path d="M9 3m0 2a2 2 0 0 1 2 -2h2a2 2 0 0 1 2 2v0a2 2 0 0 1 -2 2h-2a2 2 0 0 1 -2 -2z" /></svg>';
  var CHECK = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M5 12l5 5l10 -10" /></svg>';
  // keep only shell-command lines: strip the `$ ` prompt, carry `\`-continuations, drop output.
  function cliText(code) {
    var lines = code.textContent.replace(/\n+$/, '').split('\n');
    var out = [], cont = false;
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*\$\s?(.*)$/);
      if (m) { out.push(m[1]); cont = /\\\s*$/.test(m[1]); }
      else if (cont) { out.push(lines[i]); cont = /\\\s*$/.test(lines[i]); }
    }
    return out.length ? out.join('\n') : code.textContent.replace(/\n+$/, '');
  }
  document.querySelectorAll('pre.highlight > code.cli_example').forEach(function (code) {
    var pre = code.parentNode;
    if (pre.querySelector('.cli-copy-btn')) { return; }        // idempotent
    if (code.textContent.replace(/\n+$/, '').indexOf('\n') !== -1) { return; }  // one-line examples only
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'cli-copy-btn';
    btn.title = 'Copy command';
    btn.setAttribute('aria-label', 'Copy command');
    btn.innerHTML = CLIP;
    function ack() {
      btn.innerHTML = CHECK; btn.classList.add('copied'); btn.title = 'Copied';
      setTimeout(function () {
        btn.innerHTML = CLIP; btn.classList.remove('copied'); btn.title = 'Copy command';
      }, 1200);
    }
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      var text = cliText(code);
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(ack).catch(function () {});
      } else {                                                  // legacy fallback
        var ta = document.createElement('textarea');
        ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
        document.body.appendChild(ta); ta.select();
        try { document.execCommand('copy'); ack(); } catch (err) {}
        document.body.removeChild(ta);
      }
    });
    pre.appendChild(btn);
  });
});

/* Nav-label code symbols.  A sidebar label like "CMK Virtual Machine (__vm__)"
 * carries a code dotpath/glyph in trailing parens.  Wrap that parenthetical in a
 * <span class="nav-sym"> so CSS can render it small/tight/muted/mono.  Only wrap
 * when it LOOKS like code
 * (contains one of . * _ | /), so prose parentheticals like "(ish)" / "(loadf)"
 * are left as normal text.  Leaf links only (skip anchors with child elements,
 * e.g. section toggles). */
document.addEventListener('DOMContentLoaded', function () {
  var reSym = /^(.+?\S)\s+(\([^()]*[._*|\/][^()]*\))\s*$/;
  document.querySelectorAll('.wy-menu-vertical a').forEach(function (a) {
    if (a.children.length) { return; }
    var m = a.textContent.match(reSym);
    if (!m) { return; }
    a.textContent = m[1];
    var span = document.createElement('span');
    span.className = 'nav-sym';
    span.textContent = m[2];
    a.appendChild(span);
  });
});
