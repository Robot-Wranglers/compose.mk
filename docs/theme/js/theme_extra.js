/*
 * Assign 'docutils' class to tables so styling and
 * JavaScript behavior is applied.
 *
 * https://github.com/mkdocs/mkdocs/issues/2028
 */

$('div.rst-content table').addClass('docutils');
// hljs.configure({languages:[]});hljs.initHighlightingOnLoad();
document.addEventListener('DOMContentLoaded', function() {
    // Wait for MkDocs to fully render the page including ToC
    setTimeout(function() {
        document.querySelectorAll('.wy-breadcrumbs').forEach(item => {
            item.insertAdjacentHTML('beforeend', '<li class="wy-breadcrumbs-aside"><a href="https://github.com/robot-wranglers/compose.mk/" class="icon icon-github"> Project Source</a></li>');
    });
    }, 100); // Small delay to ensure ToC is already processed
});