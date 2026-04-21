// Permalinkable prose cards (`.cmk-card` blockquotes): mirror the admonition permalink
// behaviour on the card's bold lead-in.  Give each card a stable id (slugified from its
// title), make the lead-in clickable (drops the anchor, smooth-scrolls to center, flashes
// the `nav-target` highlight), and flash on arrival via a matching hash.  Self-contained.
(function () {
  function slugify(t){
    return t.toLowerCase().trim().replace(/[^\w\s-]/g,'').replace(/[\s-]+/g,'-').replace(/^-+|-+$/g,'');
  }
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  function flash(box){
    box.scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'center' });
    box.classList.remove('nav-target');
    void box.offsetWidth;                                          // restart the flash on a repeat hit
    box.classList.add('nav-target');
  }
  function init(){
    document.querySelectorAll('.rst-content blockquote > p.cmk-card').forEach(function(lead){
      var box = lead.parentElement;                                // the blockquote card
      var title = lead.querySelector(':scope > strong');           // the bold lead-in = the title
      if(!title || title.classList.contains('cmk-card-clickable')) return;
      var id = box.id;
      if(!id){
        var base = slugify(title.textContent) || 'card';
        id = base; var i = 2;
        while(document.getElementById(id)){ id = base + '-' + (i++); }
        box.id = id;
      }
      title.classList.add('cmk-card-clickable');
      title.addEventListener('click', function(e){
        if(e.target.closest('a')) return;                          // let real links act
        if(history.pushState) history.pushState(null, '', '#' + id);
        flash(box);
      });
    });
    // Algebra cards (<details class="algebra">): the whole <summary> is natively a toggle, but we
    // want the TITLE to permalink/toast (like a cmk-card) and only the caret to collapse.  So we
    // inject a real caret element, swallow the native summary toggle, and route clicks: caret ->
    // toggle, title/header -> drop the anchor + flash, badges (real links) -> act normally.
    document.querySelectorAll('.rst-content details.algebra').forEach(function(details){
      var summary = details.querySelector(':scope > summary');
      if(!summary || summary.dataset.algebraWired) return;
      summary.dataset.algebraWired = '1';
      var clone = summary.cloneNode(true);                        // title text minus badges/caret
      clone.querySelectorAll('.algebra-badges, .algebra-caret').forEach(function(n){ n.remove(); });
      var id = details.id;
      if(!id){
        var prev = details.previousElementSibling;                // reuse a preceding <a name="..">
        if(prev && prev.tagName === 'A' && prev.getAttribute('name')){
          id = prev.getAttribute('name');
        } else {
          var base = slugify(clone.textContent) || 'algebra';
          id = base; var i = 2;
          while(document.getElementById(id)){ id = base + '-' + (i++); }
        }
        details.id = id;
      }
      var caret = document.createElement('span');
      caret.className = 'algebra-caret';
      caret.setAttribute('role', 'button');
      caret.setAttribute('tabindex', '0');
      caret.setAttribute('aria-label', details.open ? 'collapse' : 'expand');
      caret.setAttribute('title', details.open ? 'Collapse' : 'Expand');
      summary.insertBefore(caret, summary.firstChild);
      function toggle(){
        details.open = !details.open;
        caret.setAttribute('aria-label', details.open ? 'collapse' : 'expand');
        caret.setAttribute('title', details.open ? 'Collapse' : 'Expand');
      }
      summary.addEventListener('click', function(e){
        if(e.target.closest('a')) return;                         // real links (badges) act normally
        e.preventDefault();                                       // never let the native toggle fire
        if(e.target.closest('.algebra-caret')){ toggle(); return; }
        if(history.pushState) history.pushState(null, '', '#' + id);   // title -> permalink
        flash(details);
      });
      caret.addEventListener('keydown', function(e){
        if(e.key === 'Enter' || e.key === ' '){ e.preventDefault(); toggle(); }
      });
    });
    // Protocol cards (<details class="protocol">): promote the preceding <a name="..">
    // (rendered inside a <p> wrapper) to the details id, so a table link (#<name>-protocols)
    // resolves to the card and can open it on arrival.  Native summary toggle is left intact.
    document.querySelectorAll('.rst-content details.protocol').forEach(function(details){
      if(details.id) return;
      var prev = details.previousElementSibling;
      var anchor = prev && (prev.matches('a[name]') ? prev : (prev.querySelector && prev.querySelector('a[name]')));
      if(anchor && anchor.getAttribute('name')) details.id = anchor.getAttribute('name');
    });
    function flashFromHash(){
      if(!location.hash) return;
      var el = document.getElementById(decodeURIComponent(location.hash.slice(1)));
      if(!el) return;
      if(el.matches('blockquote')) flash(el);
      else if(el.matches('details.algebra, details.protocol')){ el.open = true; flash(el); }
    }
    flashFromHash();
    window.addEventListener('hashchange', flashFromHash);
  }
  if(document.readyState !== 'loading') init();
  else document.addEventListener('DOMContentLoaded', init);
})();
