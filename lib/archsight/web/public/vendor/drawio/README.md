# draw.io viewer (vendored)

Archsight shows `.drawio` files from the resources (embedded in markdown, fetched through `/api/v1/assets/`) with the official draw.io viewer, served
from here so that nothing is loaded from `viewer.diagrams.net`, `app.diagrams.net` or any other host.

- `VERSION`, `LICENSE`, `viewer-static.min.js`, `styles/`, `shapes/`, `stencils/`, `img/`, `mxgraph/`,
  `resources/dia.txt`: upstream <https://github.com/jgraph/drawio> (Apache-2.0), copied by
  `script/vendor_drawio`. Do not edit them by hand, change the tag and run the script to upgrade.
- `viewer.html`, `viewer-config.js`, `viewer-host.js`, `math-disabled/`: ours.
  - `viewer-config.js` points every path and URL of the viewer at this directory (upstream defaults to
    viewer.diagrams.net). `test/vendored_drawio_test.rb` fails when an upstream version adds a new external
    default that is not overridden.
  - `viewer.html` also holds the few style rules that make the viewer sit cleanly in the frame: no scrollbars, the
    container as wide as the frame, and the toolbar (tagged by `viewer-host.js`) flush with a single line below it.
  - `viewer.html` carries a Content-Security-Policy that blocks requests to other hosts (the bundle also knows
    Google Fonts and app.diagrams.net). A diagram that embeds an external image shows nothing there, by design.
  - `viewer-host.js` loads the diagram from `/api/v1/assets/...`, shows it read-only and reports its height to the
    page that embeds it (`frontend/src/composables/useDrawio.js`).

The frontend build (`npm run build`) must not empty this directory: it only removes `vue/` and `vue.html`.
