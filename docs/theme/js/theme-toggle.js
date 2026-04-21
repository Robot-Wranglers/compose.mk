/* Day / night mode toggle for the breadcrumbs bar (#my-toggle-id).
 * Persists the choice in localStorage and reflects the OS preference on first
 * visit; flips `data-theme` on <html>, which the Nord night-mode CSS keys off.
 * Tabler icons: moon-stars (switch to night) / brightness-up (switch to day).
 * Ported from ~/code/mattvonrocketstein/heredoc (js/theme-toggle.js). */
(function () {
  // shown in LIGHT mode -> click goes to night
  const moonIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon icon-tabler icons-tabler-outline icon-tabler-moon-stars"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M12 3c.132 0 .263 0 .393 0a7.5 7.5 0 0 0 7.92 12.446a9 9 0 1 1 -8.313 -12.454l0 .008" /><path d="M17 4a2 2 0 0 0 2 2a2 2 0 0 0 -2 2a2 2 0 0 0 -2 -2a2 2 0 0 0 2 -2" /><path d="M19 11h2m-1 -1v2" /></svg>`;
  // shown in NIGHT mode -> click goes to day
  const sunIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="icon icon-tabler icons-tabler-outline icon-tabler-brightness-up"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M12 12m-3 0a3 3 0 1 0 6 0a3 3 0 1 0 -6 0" /><path d="M12 5l0 .01" /><path d="M17 7l0 .01" /><path d="M19 12l0 .01" /><path d="M17 17l0 .01" /><path d="M12 19l0 .01" /><path d="M7 17l0 .01" /><path d="M5 12l0 .01" /><path d="M7 7l0 .01" /></svg>`;

  // default to DAY when the user has expressed no preference (ignore OS setting)
  const saved = localStorage.getItem('theme') || 'light';
  document.documentElement.setAttribute('data-theme', saved);

  document.addEventListener('DOMContentLoaded', function () {
    const btn = document.getElementById('my-toggle-id');
    if (!btn) return;
    btn.innerHTML = saved === 'dark' ? sunIcon : moonIcon;
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      localStorage.setItem('theme', next);
      btn.innerHTML = next === 'dark' ? sunIcon : moonIcon;
    });
  });
})();
