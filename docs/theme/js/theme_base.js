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
    const img = Object.assign(document.createElement('img'), 
        {src: imgSrc}, {style: 'height:1.2em;margin-right:5px; vertical-align: middle;'+style});
    // Insert the image before the first child of the heading
    heading.insertBefore(img, heading.firstChild);
}
 
  document.addEventListener('DOMContentLoaded', function() {
    // Wait for MkDocs to fully render the page including ToC
    setTimeout(function() {
        // prominent link to project source
        document.querySelectorAll('.wy-breadcrumbs').forEach(item => {
            item.insertAdjacentHTML('beforeend', '<li class="wy-breadcrumbs-aside"><a href="{{config.site_source_url}}" class="icon icon-github">&nbsp;&nbsp;Project Source</a></li>');
        });
        
        // renders markdown content in collapsed-includes
        document.querySelectorAll('div.markdown').forEach(block => { 
          const markdownText = block.textContent || block.innerText;
          block.innerHTML = marked.parse(markdownText);
        });
      
        document.querySelectorAll('div.cli_example').forEach(block => { 
            block.className+=" language-bash language-shell-session";
            Prism.highlightElement(block); });
        
        document.querySelectorAll('div.highlight').forEach(block => {
            Prism.highlightElement(block); });
        
        // differentiate code_table_top for snippets vs embeds
        document.querySelectorAll('div.snippet').forEach(block => {
            // block.insertAdjacentHTML('beforebegin', '');
            const newDiv = new DOMParser().parseFromString('<div class=code_table_top_snippet><span class=code_table_1>&nbsp;&nbsp;&nbsp;EXAMPLE:</span><span class=code_table_2>&nbsp;&nbsp;</span><span class=code_table_3>&nbsp;&nbsp;</span></div>','text/html').body.firstChild;
            block.parentNode.insertBefore(newDiv, block);});

        // After a nav click (full page load), the RTD theme often leaves the
        // active/expanded sidebar item scrolled out of view.  Smoothly nudge the
        // sidebar so that item lands HALFWAY between its current spot and the
        // vertical center of the sidebar viewport (a soft centering, keeping the
        // item AND its just-expanded children on screen).
        const side = document.querySelector('.wy-side-scroll') || document.querySelector('.wy-nav-side');
        if (side) {
            const currents = Array.from(side.querySelectorAll('li.current'));
            // the deepest `.current` li is the active page's item
            const active = currents.filter(li => !li.querySelector('li.current')).pop() || currents.pop();
            const link = active && (active.querySelector('a') || active);
            if (link) {
                const r = link.getBoundingClientRect();
                const elCenterInView = (r.top + r.bottom) / 2 - side.getBoundingClientRect().top;
                const viewCenter = side.clientHeight / 2;
                // shift = half the distance from the item's current position to center
                let target = side.scrollTop + (elCenterInView - viewCenter) / 2;
                target = Math.max(0, Math.min(target, side.scrollHeight - side.clientHeight));
                const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
                side.scrollTo({ top: target, behavior: reduce ? 'auto' : 'smooth' });
            }
        }

    }, 100);}); // Small delay to ensure ToC is already processed