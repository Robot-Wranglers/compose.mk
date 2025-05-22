/*
 * Assign 'docutils' class to tables so styling and
 * JavaScript behavior is applied.
 *
 * https://github.com/mkdocs/mkdocs/issues/2028
 */

$('div.rst-content table').addClass('docutils');
document.addEventListener('DOMContentLoaded', function() {
    // Wait for MkDocs to fully render the page including ToC
    setTimeout(function() {
        // prominent link to project source
        document.querySelectorAll('.wy-breadcrumbs').forEach(item => {
            item.insertAdjacentHTML('beforeend', '<li class="wy-breadcrumbs-aside"><a href="https://github.com/robot-wranglers/compose.mk/" class="icon icon-github"> Project Source</a></li>');
        
        compose_keywords={'cmk-compose-keyword': {pattern: /.*(stop|build|ps) /, alias:"token p .ni .ne"} };
        Prism.languages.insertBefore('bash', 'keyword', compose_keywords);
        Prism.languages.insertBefore('make', 'keyword', compose_keywords);
            
        cmk_cli_token={'cmk-cli-token': {pattern: / (?:compose[.]mk|[.]\/compose.mk)/,} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_cli_token);
        Prism.languages.insertBefore('makefile', 'keyword', cmk_cli_token);
        
        cmk_syntax={'cmk-syntax': {pattern: /(▰|⫻|\$|〚|⟧|⋙|🞹|⋘)/,}};
        Prism.languages.insertBefore('bash', 'punctuation', cmk_syntax);
        Prism.languages.insertBefore('makefile', 'punctuation', cmk_syntax);
        
        line_feed={'cmk-line-feed': {pattern: /(\\)/,alias:"si punctuation"}};
        Prism.languages.insertBefore('bash', 'punctuation', line_feed);
        Prism.languages.insertBefore('makefile', 'punctuation', line_feed);
        
        Prism.languages.insertBefore('makefile', 'target', 
            {'cmk-dunder': {pattern: /(__main__|__init__|__name__)/,}});
        
        Prism.languages.insertBefore('bash', 'keyword', {
            'cmk-fpath': {
                pattern: /[.]\/(?:\.?\.?\/)?[\w.-]+\/[\w./-]+/, 
                alias:"token no"} });
        
        // FXN REGEX: slightly different for bash vs makefile
        // cmk_fxn=;
        Prism.languages.insertBefore('bash', 'keyword', 
            {'cmk-fxn': {
                pattern: /(?:io|log|docker|flux|mk|stream|tux)[.]([a-z._])+(?:(\/))/,} });
        Prism.languages.insertBefore('makefile', 'keyword', 
            {'cmk-fxn': {
                pattern: /(?:io|log|cmk|docker|flux|mk|stream|tux)[.]([a-z._])+(?:(\/|,|\())/,} });
        
        // must be before cmk_args 
        cmk_cli_keywords={'cmk-cli-keyword': {pattern: /\b(loadf|jb|jq)\b/, alias:"token p"} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_cli_keywords);
        Prism.languages.insertBefore('make', 'punctuation', cmk_cli_keywords);

        
        cmk_args={'cmk-args': {
            pattern: /(?:[\w.-]+)(?:,(?:[\w.-]+))+/, 
            alias:"token .ni .ne"} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_args);
        Prism.languages.insertBefore('makefile', 'target', cmk_args);
        
        // Prism.languages.insertBefore('bash', 'keyword', {'cmk-fxn': {pattern: /\bio.print.banner.*\b/,} });
        Prism.languages.insertBefore('makefile', 'keyword', 
            {'cmk-recursion': {pattern: /\b(?:make|self|this)/,} });
        
        // Prism.languages.insertBefore('bash', 'keyword', 
        //     {'cmk-path': {pattern: / (?:[.]\/)(?!compose.mk\b).*\b/, alias:"token name"} });
        // Prism.languages.insertBefore('bash', 'keyword', {'cmk-fxn': {pattern: /\b[\w.-]+\/[\w./-]+(?:,[\w./-]+)*\b/,} });
            // Prism.plugins.customClass.add(({language, type, content}) => {
        //     console.log({language, type, content});
        //     if (content === './compose.mk' ) {return 'cmk-token';}
        // });(?:flux|io)
        
        const wrapTextNodeWithSpan = (text, classes) => {                     
            const span = document.createElement('span');
            span.textContent = text.nodeValue; // Reuse the text node's value
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
            // if (node.nodeType === Node.TEXT_NODE) {
            //     console.log(node.nodeName);
            // } 
            // else {
            //     console.log(node.nodeName);
            //     // console.log(node.innerHTML);
            // }
        }); 
        
        
        
        
        
        
        
        document.querySelectorAll('div.cli_example').forEach(block => { 
            block.className+=" language-bash language-shell-session";
            Prism.highlightElement(block); });
        document.querySelectorAll('div.highlight').forEach(block => {
            Prism.highlightElement(block); });
        document.querySelectorAll('span.keyword-define').forEach(span => {
            let current = span.nextElementSibling;
            // Skip the first element after define
            if (current && !current.classList.contains('keyword-endef')) {
                current = current.nextElementSibling;
            }
            // Now apply opacity to remaining elements until endef
            while (current && !current.classList.contains('keyword-define') && (current.innerHTML.contains && !current.innerHTML.includes("define")) && !current.classList.contains('keyword-endef')) {
                console.log(current);
                current.classList.add('inside_define')
                current = current.nextElementSibling;
            }
        });
        
        // differentiate code_table_top for snippets vs embeds
        document.querySelectorAll('div.snippet').forEach(block => {
            // block.insertAdjacentHTML('beforebegin', '');
            const newDiv = new DOMParser().parseFromString('<div class=code_table_top_snippet><span class=code_table_1>&nbsp;&nbsp;&nbsp;EXAMPLE:</span><span class=code_table_2>&nbsp;&nbsp;</span><span class=code_table_3>&nbsp;&nbsp;</span></div>','text/html').body.firstChild;
            block.parentNode.insertBefore(newDiv, block);});
        
        // special handling for define blocks
        // wrapContiguousDefineBlocks();
    
    }, 100); // Small delay to ensure ToC is already processed
    })})

function toggleCodeBlock(id, link) {
    const codeBlock = document.getElementById(id);
    const isHidden = codeBlock.style.display === "none";
    codeBlock.style.display = isHidden ? "block" : "none";
    link.textContent = isHidden ? "⮝" : "⮟";
}
/**
 * Find contiguous blocks of spans with class "inside_define" and wrap them in divs
 * Plain text nodes between spans with the class should be included in the blocks
 * Newlines and <br> tags don't break continuity
 */
function wrapContiguousDefineBlocks() {
    // Get the container element to process
    const container = document.body;
    
    // Store nodes and tracking variables for each block
    let currentNodes = [];
    let hasDefineSpan = false;
    
    // Use a TreeWalker to navigate through all nodes
    const walker = document.createTreeWalker(
      container,
      NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT,
      null,
      false
    );
    
    let currentNode = walker.nextNode();
    
    while (currentNode) {
      const nextNode = walker.nextNode(); // Get next node before modifications
      
      if (currentNode.nodeType === Node.ELEMENT_NODE &&
          currentNode.tagName === 'SPAN' &&
          currentNode.classList.contains('inside_define')) {
        // Found a defining span
        currentNodes.push(currentNode);
        hasDefineSpan = true;
      }
      else if (currentNode.nodeType === Node.TEXT_NODE ||
              (currentNode.nodeType === Node.ELEMENT_NODE && currentNode.tagName === 'BR')) {
        // Text nodes and <br> tags - add to current collection
        if (currentNodes.length > 0 || nextNode) {
          currentNodes.push(currentNode);
        }
      }
      else if (currentNode.nodeType === Node.ELEMENT_NODE) {
        // Other element - this breaks the block
        if (hasDefineSpan && currentNodes.length > 0) {
          // We have a complete block - wrap it
          wrapNodesInDefineBlock(currentNodes);
        }
        
        // Reset for next block
        currentNodes = [];
        hasDefineSpan = false;
      }
      
      currentNode = nextNode;
    }
    
    // Handle any remaining block at the end
    if (hasDefineSpan && currentNodes.length > 0) {
      wrapNodesInDefineBlock(currentNodes.slice(1));
    }
  }
  
  /**
   * Wrap a set of nodes in a div with class "define_block"
   * @param {Array} nodes - Array of nodes to wrap
   */
  function wrapNodesInDefineBlock(nodes) {
    if (nodes.length === 0) return;
    
    // Create a new div with class "define_block"
    const defineBlockDiv = document.createElement('span');
    defineBlockDiv.className = 'define_block';
    
    // Insert the div before the first node
    const firstNode = nodes[0];
    firstNode.parentNode.insertBefore(defineBlockDiv, firstNode);
    
    // Move all nodes into the div
    nodes.forEach(node => {
      defineBlockDiv.appendChild(node);
    });
  }
  
//   // Run the function when the DOM is fully loaded
//   document.addEventListener('DOMContentLoaded',);
  
//   // Or run immediately if the DOM is already loaded
//   if (document.readyState === 'complete' || document.readyState === 'interactive') {
//     wrapContiguousDefineBlocks();
//   }