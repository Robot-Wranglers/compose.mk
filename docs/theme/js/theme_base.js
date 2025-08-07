function toggleCodeBlock(id, link) {
    const codeBlock = document.getElementById(id);
    const isHidden = codeBlock.style.display === "none";
    codeBlock.style.display = isHidden ? "block" : "none";
    link.textContent = isHidden ? "⮝" : "⮟";
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
                
    }, 100);}); // Small delay to ensure ToC is already processed