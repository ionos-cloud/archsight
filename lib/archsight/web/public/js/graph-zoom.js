// Graphviz SVG initialization with svg-pan-zoom (uses shared controls from svg-zoom-controls.js)
document.addEventListener('graphviz:ready', function(e) {
  var elementId = e.detail.elementId;
  var container = document.getElementById(elementId);
  if (!container) return;

  var svg = container.querySelector('svg');
  if (!svg) return;

  // Find the graph container wrapper for positioning controls
  var graphContainer = container.closest('.graph-container');
  if (!graphContainer) {
    graphContainer = container;
  }

  // Use shared initialization from svg-zoom-controls.js
  initSvgPanZoom(svg, graphContainer);
});
