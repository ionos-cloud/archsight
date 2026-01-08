// Shared zoom controls for SVG pan-zoom instances (mermaid, graphviz)
function createSvgZoomControls(container, panZoomInstance) {
  // Don't add controls if already present
  if (container.querySelector('.svg-zoom-controls')) return;

  var controls = document.createElement('div');
  controls.className = 'svg-zoom-controls';
  controls.innerHTML = `
    <button class="svg-zoom-btn" data-action="zoom-out" title="Zoom out">
      <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M19 13H5v-2h14v2z"/></svg>
    </button>
    <button class="svg-zoom-btn" data-action="zoom-in" title="Zoom in">
      <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
    </button>
    <button class="svg-zoom-btn" data-action="reset" title="Reset view">
      <svg viewBox="0 0 24 24" width="20" height="20"><path fill="currentColor" d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>
    </button>
  `;

  controls.querySelector('[data-action="zoom-in"]').addEventListener('click', function() {
    panZoomInstance.zoomIn();
  });
  controls.querySelector('[data-action="zoom-out"]').addEventListener('click', function() {
    panZoomInstance.zoomOut();
  });
  controls.querySelector('[data-action="reset"]').addEventListener('click', function() {
    panZoomInstance.resetZoom();
    panZoomInstance.resetPan();
    panZoomInstance.fit();
    panZoomInstance.center();
  });

  container.style.position = 'relative';
  container.appendChild(controls);
}

// Helper to initialize svg-pan-zoom on an SVG element
function initSvgPanZoom(svg, container) {
  // Fix viewBox to include all content with padding
  var bbox = svg.getBBox();
  var padding = 20;
  var viewBox = (bbox.x - padding) + ' ' + (bbox.y - padding) + ' ' +
                (bbox.width + padding * 2) + ' ' + (bbox.height + padding * 2);
  svg.setAttribute('viewBox', viewBox);

  // Calculate ideal container height based on SVG content
  var contentWidth = bbox.width + padding * 2;
  var contentHeight = bbox.height + padding * 2;
  var containerWidth = container.clientWidth || 800;
  var aspectRatio = contentHeight / contentWidth;

  // Calculate height that maintains aspect ratio, with min/max limits
  var idealHeight = Math.round(containerWidth * aspectRatio);
  var minHeight = 150;
  var maxHeight = Math.round(window.innerHeight * 0.7); // 70vh
  var finalHeight = Math.max(minHeight, Math.min(idealHeight + 60, maxHeight)); // +60 for controls

  // Set container height dynamically
  container.style.height = finalHeight + 'px';

  // Remove fixed dimensions
  svg.removeAttribute('width');
  svg.removeAttribute('height');
  svg.removeAttribute('style');
  svg.style.cssText = 'max-width: none !important; width: 100%; height: 100%;';

  var panZoomInstance = svgPanZoom(svg, {
    zoomEnabled: true,
    controlIconsEnabled: false,
    fit: true,
    contain: false,
    center: true,
    minZoom: 0.1,
    maxZoom: 10,
    zoomScaleSensitivity: 0.3
  });

  // Add controls
  createSvgZoomControls(container, panZoomInstance);

  // Resize handler
  var resizeHandler = function() {
    panZoomInstance.resize();
    panZoomInstance.fit();
    panZoomInstance.center();
  };
  window.addEventListener('resize', resizeHandler);

  // Initial fit after a short delay
  setTimeout(resizeHandler, 100);

  return panZoomInstance;
}
