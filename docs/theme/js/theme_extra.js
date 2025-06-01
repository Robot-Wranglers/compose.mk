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
            
        Prism.languages.cmk={
        comment:{pattern:/(^|[^\\])#(?:\\(?:\r\n|[\s\S])|[^\\\r\n])*/,lookbehind:!0},string:{pattern:/(["'])(?:\\(?:\r\n|[\s\S])|(?!\1)[^\\\r\n])*\1/,greedy:!0},"builtin-target":{pattern:/\.[A-Z][^:#=\s]+(?=\s*:(?!=))/,alias:"builtin"},
        target:{pattern:/^[^:=\s]+(?=\s*:(?!=))/m, alias:"symbol",inside:{variable:/\$+(?:(?!\$)[^(){}:#=\s]+|(?=[({]))/}},
        variable:/\$+(?:(?!\$)[^(){}:#=\s]+|\([@*%<^+?][DF]\)|(?=[({]))/,
        keyword:/-include\b|\b(?:define|else|endef|endif|export|ifn?def|ifn?eq|include|override|private|sinclude|undefine|unexport|vpath)\b/,
        function:{pattern:/(\()(?:abspath|addsuffix|and|basename|call|dir|error|eval|file|filter(?:-out)?|findstring|firstword|flavor|foreach|guile|if|info|join|lastword|load|notdir|or|origin|patsubst|realpath|shell|sort|strip|subst|suffix|value|warning|wildcard|word(?:list|s)?)(?=[ \t])/,lookbehind:!0},
        operator:/(?:::|[?:+!])?=|[|@]/,
        punctuation:/[:;(){}]/}
        
        compose_keywords={'cmk-compose-keyword': {pattern: /.*(stop|build|ps) /, alias:"token p .ni .ne"} };
        Prism.languages.insertBefore('bash', 'keyword', compose_keywords);
        Prism.languages.insertBefore('make', 'keyword', compose_keywords);
        Prism.languages.insertBefore('cmk', 'keyword', 
            {'cmk-dockerfile-kw': {pattern: /(RUN |FROM |ENV |SHELL |ENTRYPOINT |COMMAND )/, alias:"token target p .ni .ne"}});
        
        cmk_cli_token={'cmk-cli-token': {pattern: / (?:compose[.]mk|[.]\/compose.mk)/,} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_cli_token);
        Prism.languages.insertBefore('makefile', 'keyword', cmk_cli_token);
        
        cmk_syntax={'cmk-syntax': {pattern: /(▰|⫻|\$|⟦|⟧|⋙|🞹|⋘)/,}};
        Prism.languages.insertBefore('bash', 'punctuation', cmk_syntax);
        Prism.languages.insertBefore('makefile', 'punctuation', cmk_syntax);
        
        cmk_syntax={'cmk-compose-keyword': {pattern: /([.](dispatch)(\\|,))/,}};
        Prism.languages.insertBefore('bash', 'keyword', cmk_syntax);
        Prism.languages.insertBefore('makefile', 'keyword', cmk_syntax);
        Prism.languages.insertBefore('makefile', 'punctuation', cmk_syntax);
        cmk_syntax={'cmk-compose-keyword': {pattern: /[.](run).*/,}};
        Prism.languages.insertBefore('bash', 'keyword', cmk_syntax);
        Prism.languages.insertBefore('makefile', 'keyword', cmk_syntax);
        
        line_feed={'cmk-line-feed': {
            pattern: /(\\|▰|⫻|\$|⟦|⟧|⋙|🞹|⋘)/,alias:"si punctuation cmk-syntax"}};
        Prism.languages.insertBefore('bash', 'punctuation', line_feed);
        Prism.languages.insertBefore('makefile', 'punctuation', line_feed);
        
        Prism.languages.insertBefore('makefile', 'target', 
            {'cmk-dunder': {pattern: /(__main__|__init__|__name__)/,}});
            Prism.languages.insertBefore('makefile', 'target', 
                {'cmk-dockerfile-kw': {pattern: /(RUN|FROM)/,}});
        Prism.languages.insertBefore('bash', 'keyword', {
            'cmk-fpath': {
                pattern: /[.]\/(?:\.?\.?\/)?[\w.-]+\/[\w./-]+/, 
                alias:"token no"} });
        Prism.languages.insertBefore('makefile', 'comment', {
            'cmk-shebang': {
                pattern: /[#][!].*/, 
                alias:"shebang important"},
                'cmk-div': {
                    pattern: /:::/, 
                    // alias:"punctuation importan"
                    },                
            'cmk-dockerfile': {
                pattern: /(?<=Dockerfile.).*?(?=[ \n])/g,
                alias:"important"},
            // 'cmk-as-statement': {
            //     pattern: /^(?!#).*with.*(?<=as ).*?(?=\n|$)/g,
            //     alias: "important"
            // },
        });
        
        Prism.languages.insertBefore('bash', 'keyword', {
            'cmk-fpath': {
                pattern: /[.]\/(?:\.?\.?\/)?[\w.-]+\/[\w./-]+/, 
                alias:"token no"},
            // FXN REGEX: slightly different for bash vs makefile
            'cmk-fxn': {
                pattern: /(?:io|log|docker|Dockerfile|flux|stage|mk|stream|tux)[.]([a-z._])+(?:(\/))/,},
        });
        
        Prism.languages.makefile.target = {
            pattern: /^(?!⨖)[^\s:]+(?=\s*:(?!=))/m,
            alias: 'symbol'
        };
        
        // must be before cmk_args 
        cmk_cli_keywords={'cmk-cli-keyword': {pattern: /\b(loadf|jb|jq)\b/, alias:"token p"} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_cli_keywords);
        Prism.languages.insertBefore('make', 'punctuation', cmk_cli_keywords);

        cmk_args={'cmk-args': {
            pattern: /(?:[\w.-]+)(?:,(?:[\w.-]+))+/, 
            alias:"token .ni .ne"} };
        Prism.languages.insertBefore('bash', 'keyword', cmk_args);
        Prism.languages.insertBefore('makefile', 'target', cmk_args);
        
        Prism.languages.insertBefore('makefile', 'keyword', {
            'backtick-content': {
                pattern: /`[^`\n]*`/,
                inside: {
                    'punctuation': /`/
                }
            },
            'cmk-recursion': {pattern: /\b(?:make|self|this)/,}, 
            'cmk-syntax': {pattern: /(?:dispatch|run|compose[.]import.* )/,},
            'shell-command': {
                pattern: /(?:echo|cat|apk|wget|tar|apt-get|pip3|pip|npm|ansible) /,
                // alias:'important'
                },
            'shell-install': {
                pattern: /(?:apk|apt-get) /,
                // alias:''
            },
            'cmk-fxn': {
                pattern: /(?:io|log|cmk|docker|Dockerfile|flux|stage|mk|stream|tux)[.]([a-z._])+(?:(\/|,|\())/,},
            'cmk-integral-open':{
                pattern: /^⨖(?!\s+with\b).*$/m,
                inside: {
                    'symbol': /^⨖/,
                    'defname': /\b.*\b/,
                }, alias:'token cmk-line-feed si punctuation cmk-syntax'},
            // 'cmk-integral-close':{
            //     pattern: /^⨖\s+with.+$/g,
            //     alias:'token cmk-line-feed si punctuation cmk-syntax',
            //     inside: { zonk: / as /, },
            'cmk-integral-close': {
                pattern: /⨖\s+with\s+(?:[^\r\n]*(?:\r?\n(?!\s*$))*)*[^\r\n]*/gm,
                greedy: true,
                // alias:'token',
                inside: {
                    'symbol': /^⨖/,
                    'keyword-with': /\bwith\b/,
                    'keyword-as': /\bas\b/,
                    // 'with-value': /(?<=with\s+)\S+(?=\s+as)/,
                    // 'as-value': /(?<=as\s+)\S+$/
                    'keyword': /\b(?:with|as)\b/,
                    // 'with-value': /\b(?!as)\w+\b/,
                    'as-value':  /\b\w+\b$/,
                    'with-value': /(?<![a-zA-Z0-9_])(?!as)[\w\/\:]+(?![a-zA-Z0-9_])/,
                    }
            },
           // 'cmk-with':{
            //     pattern: /(?<=^⨖\s+with\s+)\S+/gm,
            //     alias:'token cmk-line-feed si punctuation cmk-syntax'},
                // 'cmk-keyword': {
            //     pattern: /(?: with | as )/,
            // },
            });
        // Prism.languages.insertBefore('makefile', 'keyword', 
        //     {'cmk-syntax': {pattern: /(?:dispatch|run)/,} });
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


// function addImageToHeader(headerId, imgSrc) {
//     const processedHeaderId = headerId.replace(/\s+/g, '-');
//     // Get the heading element
//     const heading = document.getElementById(processedHeaderId);
//     // Check if heading exists
//     if (!heading) {
//       console.error(`Element with ID '${processedHeaderId}' not found`);
//       return;
//     }
//     img = Object.assign(document.createElement('img'), 
//         {src: imgSrc}, {style: 'height: 1.2em; margin-right:5px; vertical-align: middle;'});
    
//     heading.insertBefore(img, heading.firstChild);
//   }
  function addImageToHeader(headerId, imgSrc,style="") {
    // Convert spaces to dashes in header-id
    const processedHeaderId = headerId.replace(/\s+/g, '-');
    const headers = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
    // First try exact match (case-insensitive)
    let heading = Array.from(headers).find(h => 
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
// const img = document.createElement('img');
//     img.style.verticalAlign = 'middle';
//     img.src = imgSrc;
//     img.style.marginRight = '10px';
    
    // Insert the image before the first child of the heading
    heading.insertBefore(img, heading.firstChild);
  }
  
  // Example usage:
  // addImageToHeader('overview', '../img/road_map.svg'); // Exact match
  // addImageToHeader('section', '../img/icon.png'); // Could match 'section-1', 'section-intro', etc.
  // addImageToHeader('intro', '../img/icon.png'); // Could match 'section-intro-text' via substring
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