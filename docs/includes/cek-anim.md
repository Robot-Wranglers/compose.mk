<div align="center" style="margin:0.6em 0;">
<div class="cek-anim" role="img"
     aria-label="CMK is a CEK machine: the M rotates sideways to become a sigma (Σ)"
     title="click to pause — the M turns sideways into a Σ (CMK is a CEK machine)">
<span>C</span><span class="cek-mid"><b class="cek-m">M</b><b class="cek-e">Σ</b></span><span>K</span>
</div>
</div>
<style>
.cek-anim{
  display:inline-flex; align-items:center; gap:.14em;
  font-family:"Consolas","DejaVu Sans Mono","Liberation Mono",monospace; font-weight:800;
  font-size:2.6rem; line-height:1; letter-spacing:.06em;
  padding:.28em .6em; border-radius:8px; background:rgba(255,255,255,0.04);
  cursor:pointer;   /* click toggles the animation (see the script below) */
}
/* Click-to-pause: freeze the M/Σ mid-flight (reversible -- click again to resume). */
.cek-anim.cek-paused .cek-m,
.cek-anim.cek-paused .cek-e{ animation-play-state: paused; }
.cek-anim .cek-mid{ position:relative; display:inline-block; width:1ch; height:1em; }
.cek-anim .cek-m,.cek-anim .cek-e{
  position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
}
.cek-anim .cek-m{ animation: cek-m 8s cubic-bezier(.7,0,.3,1) infinite; }
.cek-anim .cek-e{ animation: cek-e 8s cubic-bezier(.7,0,.3,1) infinite; color:#88c0d0; }
@keyframes cek-m{
  0%,32%  { opacity:1; transform:rotate(0deg); }
  46%,86% { opacity:0; transform:rotate(90deg); }
  100%    { opacity:1; transform:rotate(0deg); }
}
@keyframes cek-e{
  0%,32%  { opacity:0; transform:rotate(-90deg); }
  46%,86% { opacity:1; transform:rotate(0deg); }
  100%    { opacity:0; transform:rotate(-90deg); }
}
@media (prefers-reduced-motion: reduce){
  .cek-anim .cek-m,.cek-anim .cek-e{ animation:none; transform:none; }
  .cek-anim .cek-e{ opacity:0; }
  .cek-anim .cek-m{ opacity:1; }
}
</style>
<script>
/* Toggle the CEK animation on click: first click pauses (freezes the M/Σ in
   place), the next resumes.  Idempotent + self-scoped, so the include is safe on
   every page it appears (cmk landing, runtime).  The element already precedes
   this inline script in the DOM, so no load-event wait is needed. */
(function(){
  document.querySelectorAll('.cek-anim').forEach(function(el){
    if (el.dataset.cekBound) return;
    el.dataset.cekBound = '1';
    el.addEventListener('click', function(){ el.classList.toggle('cek-paused'); });
  });
})();
</script>
