// Mermaid diagram initialization with dark mode support
function getMermaidTheme() {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default';
}

mermaid.initialize({
  startOnLoad: false,
  theme: getMermaidTheme()
});

// Initialize svg-pan-zoom on mermaid SVGs (uses shared createSvgZoomControls from svg-zoom-controls.js)
function initPanZoom() {
  document.querySelectorAll('.mermaid svg').forEach(function (svg) {
    if (svg.hasAttribute('data-panzoom-init')) return;
    svg.setAttribute('data-panzoom-init', 'true');

    var container = svg.parentElement;

    // Fix viewBox to include all content with padding
    var bbox = svg.getBBox();
    var padding = 20;
    var viewBox = (bbox.x - padding) + ' ' + (bbox.y - padding) + ' ' +
                  (bbox.width + padding * 2) + ' ' + (bbox.height + padding * 2);
    svg.setAttribute('viewBox', viewBox);

    // Remove fixed dimensions
    svg.removeAttribute('width');
    svg.removeAttribute('height');
    svg.removeAttribute('style');
    svg.style.cssText = 'max-width: none !important; width: 100%; height: 100%;';

    var panZoomInstance = svgPanZoom(svg, {
      zoomEnabled: true,
      controlIconsEnabled: false,  // Use custom controls
      fit: true,
      contain: false,
      center: true,
      minZoom: 0.1,
      maxZoom: 10,
      zoomScaleSensitivity: 0.3
    });

    // Add shared zoom controls
    createSvgZoomControls(container, panZoomInstance);

    // Resize handler
    var resizeHandler = function() {
      panZoomInstance.resize();
      panZoomInstance.fit();
      panZoomInstance.center();
    };
    window.addEventListener('resize', resizeHandler);

    // Initial fit after a short delay to ensure container is sized
    setTimeout(resizeHandler, 100);
  });
}

function renderMermaid() {
  document.querySelectorAll('pre > code.language-mermaid').forEach(function (codeBlock) {
    var pre = codeBlock.parentElement;
    var div = document.createElement('div');
    div.className = 'mermaid';
    div.setAttribute('data-mermaid-source', codeBlock.textContent);
    div.textContent = codeBlock.textContent;
    pre.parentElement.replaceChild(div, pre);
  });
  mermaid.run().then(initPanZoom);
}

// Re-initialize mermaid when color scheme changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
  mermaid.initialize({
    startOnLoad: false,
    theme: getMermaidTheme()
  });
  document.querySelectorAll('.mermaid[data-mermaid-source]').forEach(function (el) {
    el.removeAttribute('data-processed');
    el.innerHTML = el.getAttribute('data-mermaid-source');
  });
  mermaid.run().then(initPanZoom);
});

// Render on initial page load and set up HTMX listener
document.addEventListener('DOMContentLoaded', function () {
  renderMermaid();
  document.body.addEventListener('htmx:afterSwap', renderMermaid);
});
