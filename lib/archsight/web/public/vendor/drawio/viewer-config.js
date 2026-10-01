/* Points the draw.io viewer at the copies of its own files that Archsight serves. Must run before
   viewer-static.min.js, which only sets each of these when it is undefined (and then to viewer.diagrams.net,
   app.diagrams.net, github.com, ...). Anything the viewer does not need is set to something harmless. */
(function () {
  'use strict';
  var origin = window.location.origin;
  var base = '/vendor/drawio';

  // where the viewer loads its own files from
  window.STYLE_PATH = base + '/styles';
  window.SHAPES_PATH = base + '/shapes';
  window.STENCIL_PATH = base + '/stencils';
  window.GRAPH_IMAGE_PATH = base + '/img';
  window.RESOURCES_PATH = base + '/resources';
  window.mxImageBasePath = base + '/mxgraph/images';
  window.mxBasePath = base + '/mxgraph/';
  // relative image references in diagrams (img/lib/...) are resolved against this
  window.DRAWIO_BASE_URL = origin + base;
  window.DRAWIO_SERVER_URL = origin + base + '/';

  // MathJax is not shipped: a placeholder script keeps the viewer from requesting a missing file
  window.DRAW_MATH_URL = base + '/math-disabled';

  // services of draw.io itself that a read-only viewer never uses
  window.PROXY_URL = '';
  window.SAVE_URL = '';
  window.DRAWIO_LIGHTBOX_URL = '';
  window.VSS_CONVERT_URL = '';
  window.RT_WEBSOCKET_URL = '';
  window.DRAWIO_GITLAB_URL = '';
  window.DRAWIO_GITHUB_URL = '';
  window.DRAWIO_GITHUB_API_URL = '';
})();
