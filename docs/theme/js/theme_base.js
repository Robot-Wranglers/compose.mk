function toggle_id(id, link,close="⮝", open="⮟") {
  const codeBlock = document.getElementById(id);
  const isHidden = codeBlock.style.display === "none";
  codeBlock.style.display = isHidden ? "block" : "none";
  link.textContent = isHidden ? open: close; 
}

function addImageToHeader(headerId, imgSrc,style="") {
    if (!imgSrc.endsWith('.svg') && !imgSrc.endsWith('.png')  && !imgSrc.endsWith('.jpg') ) { imgSrc += '.svg'; }
    // Convert spaces to dashes in header-id
    const processedHeaderId = headerId.toLowerCase().replace(/\s+/g, '-').replace('?','-');
    const headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6, h7');
    // First try exact match (case-insensitive)
    heading = Array.from(headers).find(h => 
      h.id && h.id.toLowerCase() === processedHeaderId.toLowerCase()
    );
    // If no exact match, try startsWith (case-insensitive)
    if (!heading) {
      heading = Array.from(headers).find(h => 
        h.id && h.id.toLowerCase().startsWith(processedHeaderId.toLowerCase())
      );
    }
    // If startsWith fails, try contains substring (case-insensitive)
    if (!heading) {
      heading = Array.from(headers).find(h => 
        h.id && h.id.toLowerCase().includes(processedHeaderId.toLowerCase())
      );
    }
    // Check if heading was found
    if (!heading) {
      console.error(`No header element found matching '${processedHeaderId}'`);
      return;
    }
    // Create and configure the image element
    // height-only (width stays auto) keeps aspect ratio intact; a small right gap
    // separates the icon from the heading label (was flush at margin-right:0).
    const img = Object.assign(document.createElement('img'),
        {src: imgSrc}, {style: 'height:1em;margin-right:0.35em;vertical-align:middle;'+style});
    // Insert the image before the first child of the heading
    heading.insertBefore(img, heading.firstChild);
}

// addPromptBadge: attach a small pill label to a header by its anchor id, client-side
// after render.  Because the badge lives in the DOM (never the markdown source) it does
// NOT leak into the header's slug/#anchor or the ToC.  The badge floats to the far-right
// of the heading (see .prompt-badge in compose.mk.css).  Header lookup mirrors
// addImageToHeader (exact id, then startsWith, then substring; all case-insensitive).
function addPromptBadge(headerId, label, tooltip) {
    label = label || 'prompt';
    tooltip = tooltip || 'promptX';
    const processedHeaderId = headerId.toLowerCase().replace(/\s+/g, '-').replace('?','-');
    const headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6, h7');
    let heading = Array.from(headers).find(h => h.id && h.id.toLowerCase() === processedHeaderId.toLowerCase());
    if (!heading) { heading = Array.from(headers).find(h => h.id && h.id.toLowerCase().startsWith(processedHeaderId.toLowerCase())); }
    if (!heading) { heading = Array.from(headers).find(h => h.id && h.id.toLowerCase().includes(processedHeaderId.toLowerCase())); }
    if (!heading) { console.error(`No header element found matching '${processedHeaderId}'`); return; }
    // flex row so the header icon, text, and badge share a common bottom edge
    // (align-items:flex-end); the badge is pushed far-right with margin-left:auto.
    heading.classList.add('has-prompt-badge');
    const badge = Object.assign(document.createElement('span'),
        {className: 'prompt-badge', textContent: label, title: tooltip});
    heading.appendChild(badge);
}

  document.addEventListener('DOMContentLoaded', function() {
    // Wait for MkDocs to fully render the page including ToC
    setTimeout(function() {
        // (project-source link now lives in breadcrumbs.html as a Tabler
        //  brand-github icon, alongside the day/night toggle -- no JS injection)

        // renders markdown content in collapsed-includes
        document.querySelectorAll('div.markdown').forEach(block => { 
          const markdownText = block.textContent || block.innerText;
          block.innerHTML = marked.parse(markdownText);
        });
      
        document.querySelectorAll('div.cli_example').forEach(block => { 
            block.className+=" language-bash language-shell-session";
            Prism.highlightElement(block); });
        
        // First-paint highlight.  Pygments is off (use_pygments:false), so fenced blocks
        // are `<pre class="highlight"><code class="language-<x>">` -- highlight the <code>,
        // skipping `.nohighlight`.  (js/theme_extra.js re-highlights authoritatively once
        // the cmk grammar is registered; this pass just avoids a flash of raw text.)
        document.querySelectorAll('pre.highlight code[class*="language-"], div.highlight code[class*="language-"]').forEach(code => {
            if (!code.classList.contains('nohighlight')) Prism.highlightElement(code); });

        // Snippets render as a ONE-TAB SOLO MIRROR -- the SAME chrome an embed_demo uses
        // (`code_mirror_solo` > `mirror_tabs` > a single active `mirror_tab` labeled
        // "Example" > `mirror_pane`), so a snippet reads as a single-tab embed.  No
        // mirror_src source-link -- an inline snippet has no file outside the docs.
        // Under use_pygments:false the `snippet` class rides on the <code> (not a wrapper
        // div), so match that and wrap its <pre>.  (`div.snippet` kept for legacy blocks.)
        document.querySelectorAll('pre.highlight > code.snippet, div.snippet').forEach(el => {
            const block = el.matches('code') ? (el.closest('pre') || el) : el;
            const solo = new DOMParser().parseFromString('<div class="code_mirror code_mirror_solo"><div class="mirror_tabs" role="tablist"><span class="mirror_tab mirror_tab_active" role="tab">Example</span></div><div class="mirror_pane" role="tabpanel"></div></div>','text/html').body.firstChild;
            block.parentNode.insertBefore(solo, block);
            solo.querySelector('.mirror_pane').appendChild(block);});

        // Responsive-table wrapping (was RTD theme.js, no longer loaded).  Wrap wide
        // docutils tables in `.wy-table-responsive` so they scroll horizontally instead of
        // overflowing; footnote/citation tables get the labelled variants the CSS expects.
        [['table.docutils:not(.field-list):not(.footnote):not(.citation)', 'wy-table-responsive'],
         ['table.docutils.footnote', 'wy-table-responsive footnote'],
         ['table.docutils.citation', 'wy-table-responsive citation']
        ].forEach(function (pair) {
          document.querySelectorAll(pair[0]).forEach(function (t) {
            if (t.closest('.wy-table-responsive')) return;
            var w = document.createElement('div');
            w.className = pair[1];
            t.parentNode.insertBefore(w, t);
            w.appendChild(t);
          });
        });

        // cmk syntax color-scheme selector (static, in the breadcrumbs top bar -- see
        // breadcrumbs.html).  Flips which prism-cmk theme <link> is active (same idea as
        // prismjs.com's theme picker); both <link>s are loaded (base.html), we just flip
        // `.disabled`.  Persisted; kept out of the code-widget chrome entirely.
        (function(){
            const KEY='cmk-color-scheme', DEFAULT='nord';
            // Data-driven over every `<link id="cmk-theme-<name>">` (base.html) -- add a
            // theme by shipping its css + <link> + a <select> <option>; no JS change needed.
            const links={};
            document.querySelectorAll('link[id^="cmk-theme-"]').forEach(l=>{ links[l.id.slice('cmk-theme-'.length)]=l; });
            const selects=document.querySelectorAll('.cmk-theme-select');
            const names=Object.keys(links);
            if(!names.length || !links[DEFAULT] || !selects.length) return;
            function apply(name){
                if(!links[name]) name=DEFAULT;               // unknown/removed theme -> default
                names.forEach(n=>{ links[n].disabled = n!==name; });
                try{ localStorage.setItem(KEY, name); }catch(e){}
                selects.forEach(s=>{ if(s.value!==name) s.value=name; });
            }
            let current=DEFAULT; try{ current=localStorage.getItem(KEY)||DEFAULT; }catch(e){}
            apply(current);
            selects.forEach(s=> s.addEventListener('change', function(){ apply(this.value); }));
        })();

    }, 100);}); // Small delay to ensure ToC is already processed