// Drag-to-resize the left navigation sidebar (desktop only).
// Persists the chosen width in localStorage; double-click the grip to reset.
(function () {
  var MIN = 200, MAX = 640, KEY = 'cmk-sidebar-w';
  var mq = window.matchMedia('(min-width: 768px)');
  var root = document.documentElement;

  function setWidth(px) { root.style.setProperty('--cmk-sidebar-w', px + 'px'); }

  function applyStored() {
    var v = parseInt(localStorage.getItem(KEY), 10);
    if (v && v >= MIN && v <= MAX) setWidth(v);
  }

  function init() {
    var side = document.querySelector('.wy-nav-side');
    if (!side || side.querySelector('.cmk-sidebar-grip')) return;

    var grip = document.createElement('div');
    grip.className = 'cmk-sidebar-grip';
    grip.title = 'Drag to resize · double-click to reset';
    side.appendChild(grip);

    var dragging = false;

    grip.addEventListener('mousedown', function (e) {
      if (!mq.matches) return;
      dragging = true;
      document.body.classList.add('cmk-sidebar-dragging');
      e.preventDefault();
    });

    document.addEventListener('mousemove', function (e) {
      if (!dragging) return;
      // sidebar hugs the viewport's left edge, so pointer X == desired width
      setWidth(Math.min(MAX, Math.max(MIN, e.clientX)));
    });

    document.addEventListener('mouseup', function () {
      if (!dragging) return;
      dragging = false;
      document.body.classList.remove('cmk-sidebar-dragging');
      var v = parseInt(getComputedStyle(root).getPropertyValue('--cmk-sidebar-w'), 10);
      if (v) localStorage.setItem(KEY, v);
    });

    grip.addEventListener('dblclick', function () {
      root.style.removeProperty('--cmk-sidebar-w');
      localStorage.removeItem(KEY);
    });
  }

  applyStored();
  if (document.readyState !== 'loading') init();
  else document.addEventListener('DOMContentLoaded', init);
})();
