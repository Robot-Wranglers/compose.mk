/*
 * Sidebar nav controller -- the SOLE authority over the sidebar tree's open/closed
 * state.  This one file replaces (a) the five stateful handlers that used to live in
 * theme_extra.js and (b) the nav behaviour of RTD's stock theme.js, which is no longer
 * loaded.  The design goal is a single source of truth so the tree stops being subtly
 * wrong: nothing else in the codebase may open or close a nav node.
 *
 * State model.  A collapsible row's <li> carries `.current` == "this branch is OPEN".
 * The server renders `.current` on the active trail (so the current page opens on load);
 * from then on ONLY this file writes it.  Chapters (the top-level captions) use a
 * separate `.collapsed` class on their `ul.nav-chapter-items` (opposite polarity, its own
 * CSS).  Both kinds animate through the SAME height helper and the SAME resting inline
 * max-height ('' = open / '0px' = closed), so there is one renderer and one mutator path.
 *
 * Interaction.  A SINGLE capture-phase click handler on `.wy-menu-vertical` intercepts
 * every nav click before it can bubble, so there is exactly one place that decides what a
 * click means (toggle a group, toggle a chapter, scroll to a section, or navigate).
 */
(function () {
  document.addEventListener('DOMContentLoaded', function () {
    var menu = document.querySelector('.wy-menu-vertical');
    if (!menu) { return; }

    var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    var sc = document.querySelector('.wy-side-scroll');   // the sidebar's own scroll container
    var here = location.pathname.replace(/\/+$/, '');
    var armed = false;                          // animate only AFTER first paint (no load jitter)
    var STORE_SLOT = 'cmk-nav-collapsed-v3';    // remembered chapter COLLAPSES only (unchanged contract)
    var store;
    try { store = JSON.parse(localStorage.getItem(STORE_SLOT)) || {}; } catch (e) { store = {}; }
    function save() { try { localStorage.setItem(STORE_SLOT, JSON.stringify(store)); } catch (e) {} }

    /* Inject the expand dot (was RTD's init()).  Prepend a `button.toctree-expand` into
     * every row <a> that owns a sibling sub-<ul>; the existing CSS renders the ○/● glyph
     * off `.current`.  Chapters use their own triangle toggle, so skip their lists. */
    menu.querySelectorAll('ul:not(.simple):not(.nav-chapter-items)').forEach(function (ul) {
      var a = ul.previousElementSibling;
      if (a && a.tagName === 'A' && !a.querySelector(':scope > button.toctree-expand')) {
        var b = document.createElement('button');
        b.className = 'toctree-expand';
        b.setAttribute('title', 'Open/close menu');
        a.insertBefore(b, a.firstChild);
      }
    });

    /* Tag every animatable row sub-list `.nav-subtree` (CSS keeps it displayed and gives
     * it the max-height transition; JS owns the inline height). */
    menu.querySelectorAll('li > ul').forEach(function (ul) {
      if (!ul.classList.contains('nav-chapter-items')) { ul.classList.add('nav-subtree'); }
    });

    function subUl(li) { return li.querySelector(':scope > ul.nav-subtree'); }

    /* ONE renderer.  Drive a box's inline max-height so `.nav-subtree` and
     * `.nav-chapter-items` glide identically.  Resting state is '' (auto, open) or '0px'
     * (closed).  animate=false (or reduced-motion) snaps; open ends back at '' so a nested
     * branch opening later can never be clipped. */
    function applyHeight(box, open, animate) {
      if (!box) { return; }
      if (!animate || reduceMotion.matches) { box.style.maxHeight = open ? '' : '0px'; return; }
      if (open) {
        var h = box.scrollHeight;
        box.style.maxHeight = '0px';
        box.getBoundingClientRect();                       // flush the start height
        box.style.maxHeight = h + 'px';
        var done = function (e) {
          if (e && e.propertyName !== 'max-height') { return; }
          box.style.maxHeight = '';                        // auto -> reflows freely
          box.removeEventListener('transitionend', done);
        };
        box.addEventListener('transitionend', done);
        setTimeout(done, 400);                             // fallback if the event is missed
      } else {
        box.style.maxHeight = box.scrollHeight + 'px';
        box.getBoundingClientRect();
        box.style.maxHeight = '0px';
      }
    }

    /* ---- tree rows ------------------------------------------------------- */
    function isOpen(li) { return li.classList.contains('current'); }
    function setOpen(li, open, animate) {
      if (isOpen(li) === open) { applyHeight(subUl(li), open, false); return; }  // resync height only
      li.classList.toggle('current', open);
      var btn = li.querySelector(':scope > a > button.toctree-expand');
      if (btn) { btn.setAttribute('aria-expanded', open ? 'true' : 'false'); }
      applyHeight(subUl(li), open, animate);
    }

    /* ---- chapters (separate `.collapsed` polarity + localStorage) -------- */
    function chapterList(cap) {
      return menu.querySelector('ul.nav-chapter-items[data-nav-chapter="' + cap.getAttribute('data-nav-chapter') + '"]');
    }
    function chapterTitle(cap) {
      var label = cap.querySelector('.caption-text');
      return label ? label.textContent : cap.getAttribute('data-nav-chapter');
    }
    function setChapter(cap, collapsed, animate, persist) {
      var list = chapterList(cap);
      if (!list) { return; }
      cap.classList.toggle('collapsed', collapsed);
      list.classList.toggle('collapsed', collapsed);
      var toggle = cap.querySelector('.nav-chapter-toggle');
      if (toggle) { toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true'); }
      applyHeight(list, !collapsed, animate);
      if (persist) {
        // Persist COLLAPSES only; an expand reverts to the server default on the next page.
        if (collapsed) { store[chapterTitle(cap)] = true; } else { delete store[chapterTitle(cap)]; }
        save();
      }
    }
    function toggleChapter(cap) { setChapter(cap, !cap.classList.contains('collapsed'), true, true); }

    // Restore remembered chapter collapses over the server default (active chapter forced open).
    menu.querySelectorAll('p.caption.nav-chapter').forEach(function (cap) {
      try {
        var list = chapterList(cap);
        if (!list) { return; }
        if (list.classList.contains('current')) {
          delete store[chapterTitle(cap)];                 // active chapter: honor the server, forget memory
        } else if (Object.prototype.hasOwnProperty.call(store, chapterTitle(cap))) {
          setChapter(cap, !!store[chapterTitle(cap)], false, false);
        } else {
          setChapter(cap, cap.classList.contains('collapsed'), false, false);  // reconcile inline height
        }
      } catch (e) { /* one bad chapter must not abort the rest */ }
    });

    /* Initial row reconciliation: height follows the server-rendered `.current`, instant
     * (we are still inside `.nav-init`, transitions off). */
    menu.querySelectorAll('li > ul.nav-subtree').forEach(function (ul) {
      applyHeight(ul, ul.parentElement.classList.contains('current'), false);
    });

    /* ---- scroll + flash a same-page section (was the section-scroll handler) --- */
    function samePageHash(a) {
      try {
        var u = new URL(a.href, location.href);
        return (u.pathname.replace(/\/+$/, '') === here && u.hash) ? u.hash : '';
      } catch (e) { return ''; }
    }
    function selfNoHash(a) {                                // the ACTIVE page's own link
      try {
        var u = new URL(a.href, location.href);
        return (!u.hash || u.hash === '#') && u.pathname.replace(/\/+$/, '') === here;
      } catch (e) { return false; }
    }
    function closeMobile() {
      var shift = document.querySelector("[data-toggle='wy-nav-shift']");
      if (shift) { shift.classList.remove('shift'); }
    }
    function scrollFlash(hash) {
      var target = document.getElementById(decodeURIComponent(hash.slice(1)));
      if (!target) { return false; }
      closeMobile();
      target.scrollIntoView({ behavior: reduceMotion.matches ? 'auto' : 'smooth', block: 'center' });
      if (history.pushState) { history.pushState(null, '', hash); }
      target.classList.remove('nav-target');
      void target.offsetWidth;                             // restart the flash on a repeat click
      target.classList.add('nav-target');
      return true;
    }

    /* Recenter the SIDEBAR (not the page) so a label -- and the block about to expand below
     * it -- comes into view, GENTLY.  Only moves when the label is above the fold or the
     * expanded content would run past the bottom, so an already-visible row never jumps
     * (that pop was the "jitter").  Reads the label rect (stable: it sits ABOVE its own
     * sub-list, so it doesn't move as the list grows) and the sub-list's full height, so the
     * target is correct even mid-expansion; `padding-bottom:50vh` (CSS) guarantees room.
     * The browser clamps the scroll and animates it. */
    function navScroll(a, extraBelow, smooth) {
      if (!sc || !a) { return; }
      var cr = sc.getBoundingClientRect(), ar = a.getBoundingClientRect();
      var need = (ar.top < cr.top + 4) || (ar.bottom + extraBelow > cr.bottom - 4);
      if (!need) { return; }
      var target = Math.max(0, sc.scrollTop + (ar.top - cr.top) - sc.clientHeight * 0.3);
      if (Math.abs(target - sc.scrollTop) < 2) { return; }
      sc.scrollTo({ top: target, behavior: (smooth && !reduceMotion.matches) ? 'smooth' : 'auto' });
    }
    function navScrollOpen(li) {                            // recenter after a user expands `li`
      var ul = subUl(li);
      navScroll(li.querySelector(':scope > a'), ul ? ul.scrollHeight : 0, true);
    }

    /* ---- deep-link branch reveal (load + hashchange) --------------------
     * Open the whole trail down to the hash target so a fragment link never lands on a
     * clamped sub-list.  Marks it owns carry `data-hash-open` and are cleared before each
     * re-sync so only the active branch stays force-open; RTD's page-level `.current` (the
     * toctree-l1 row) is never disturbed. */
    function openTrail(animate) {
      menu.querySelectorAll('li[data-hash-open]').forEach(function (li) {
        li.removeAttribute('data-hash-open');
        if (!li.classList.contains('toctree-l1')) { setOpen(li, false, animate); }
      });
      if (!location.hash || location.hash === '#') { return; }
      var link = null;
      menu.querySelectorAll('a.reference.internal').forEach(function (a) {
        if (link) { return; }
        try {
          var u = new URL(a.href, location.href);
          if (u.hash === location.hash && u.pathname.replace(/\/+$/, '') === here) { link = a; }
        } catch (e) { /* skip unparseable href */ }
      });
      if (!link) { return; }
      var li = link.closest('li');
      while (li && !li.classList.contains('toctree-l1')) {
        setOpen(li, true, animate);
        li.setAttribute('data-hash-open', '');
        li = li.parentElement ? li.parentElement.closest('li') : null;
      }
    }
    openTrail(false);
    window.addEventListener('hashchange', function () { openTrail(armed); });

    /* ---- THE single interaction handler (capture phase) ------------------
     * Capture runs before any bubbling listener, so calling stopPropagation here fully
     * preempts anything else (there is nothing else now, but it also stops accidental
     * double-handling).  Each branch decides one thing and returns. */
    menu.addEventListener('click', function (e) {
      var dot = e.target.closest('button.toctree-expand');
      if (dot) {                                           // the ○/● dot: pure toggle
        e.preventDefault(); e.stopPropagation();
        var dli = dot.closest('li');
        if (dli) {
          var willOpen = !isOpen(dli);
          setOpen(dli, willOpen, true);
          if (willOpen) { navScrollOpen(dli); }            // glide the expanded branch into view
        }
        return;
      }
      var cap = e.target.closest('p.caption.nav-chapter');
      if (cap) {                                           // chapter caption: toggle its list
        e.preventDefault(); e.stopPropagation();
        toggleChapter(cap);
        return;
      }
      var a = e.target.closest('a');
      if (!a || !menu.contains(a)) { return; }
      var li = a.closest('li');
      var group = li && subUl(li);
      var hash = samePageHash(a);
      var inPage = !!hash || selfNoHash(a);                // belongs to the current page's tree

      if (group && inPage) {                               // a group row on this page: symmetric toggle
        e.preventDefault(); e.stopPropagation();
        var wasOpen = isOpen(li);
        setOpen(li, !wasOpen, true);
        if (!wasOpen) {
          if (hash) { scrollFlash(hash); }                 // page content -> the section heading
          navScrollOpen(li);                               // sidebar -> glide the expanded branch in
        }
        return;
      }
      if (hash) {                                          // a leaf section on this page: scroll
        if (scrollFlash(hash)) { e.preventDefault(); e.stopPropagation(); }
        return;
      }
      closeMobile();                                       // cross-page leaf/parent: let it navigate
    }, true);

    /* Arm animations after the first paint and drop the `.nav-init` transition guard, so the
     * load-time reconciliation above stays instant and only USER toggles from here on glide. */
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        armed = true;
        var side = document.querySelector('.wy-nav-side.nav-init');
        if (side) { side.classList.remove('nav-init'); }
        // Reveal the active item -- the nicety RTD's neutered reset() used to provide -- but
        // as a GENTLE glide (gated: no motion if it's already visible) instead of a pop.
        var act = menu.querySelector('a.current-page') || menu.querySelector('li.current > a');
        if (act) {
          var ali = act.closest('li'), aul = ali && subUl(ali);
          navScroll(act, (aul && ali.classList.contains('current')) ? aul.scrollHeight : 0, true);
        }
      });
    });
  });

  /* Mobile hamburger (was RTD's wy-nav-top handler).  Bound on the document because the
   * toggle lives OUTSIDE `.wy-menu-vertical`; toggles the sidebar shift. */
  document.addEventListener('click', function (e) {
    var t = e.target.closest("[data-toggle='wy-nav-top']");
    if (!t) { return; }
    var shift = document.querySelector("[data-toggle='wy-nav-shift']");
    if (shift) { shift.classList.toggle('shift'); }
  });
})();
