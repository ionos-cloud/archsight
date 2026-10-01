/* Hosts the draw.io viewer inside an iframe of the Archsight UI: loads the diagram from the assets API,
   shows it read-only and tells the parent page how high it is (or why it failed). */
(function () {
  'use strict';

  var ASSET_PREFIX = '/api/v1/assets/';
  var params = new URLSearchParams(window.location.search);
  var src = params.get('src') || '';
  var diagram = document.getElementById('diagram');
  var errorBox = document.getElementById('error');
  var lastHeight = 0;

  function notify(message) {
    if (window.parent === window) { return; }
    window.parent.postMessage(Object.assign({ channel: 'archsight-drawio', src: src }, message), window.location.origin);
  }

  // The viewer builds its toolbar as an unnamed absolutely positioned div inside the container; tag it so
  // viewer.html can style it
  function tagToolbar() {
    var bar = Array.prototype.find.call(diagram.children, function (element) {
      return element.tagName === 'DIV' && window.getComputedStyle(element).position === 'absolute';
    });
    if (bar) { bar.classList.add('archsight-toolbar'); }
  }

  function reportHeight() {
    // +2: heights are fractional, a rounded-down frame would clip the last line of the drawing
    var height = Math.ceil(document.documentElement.scrollHeight) + 2;
    if (height && height !== lastHeight) {
      lastHeight = height;
      notify({ type: 'size', height: height });
    }
  }

  function fail(text) {
    diagram.hidden = true;
    errorBox.textContent = text;
    errorBox.hidden = false;
    notify({ type: 'error', message: text });
    reportHeight();
  }

  if (src.indexOf(ASSET_PREFIX) !== 0) {
    fail('This page only shows diagrams from the assets of the resources.');
    return;
  }
  if (typeof GraphViewer === 'undefined') {
    fail('The draw.io viewer is not available.');
    return;
  }

  fetch(src, { credentials: 'same-origin' })
    .then(function (response) {
      if (!response.ok) { throw new Error('The diagram could not be loaded (' + response.status + ').'); }
      return response.text();
    })
    .then(function (xml) {
      var config = {
        xml: xml,
        page: Number(params.get('page')) || 0,
        highlight: '#0000ff',
        nav: false,
        lightbox: false,
        resize: true,
        // fit the diagram to the width of the page, cut the empty margin of the draw.io page, keep fitting on resize
        'auto-fit': true,
        'auto-crop': true,
        responsive: true,
        toolbar: 'pages zoom layers',
        'toolbar-position': 'top',
        'toolbar-nohide': true
      };
      diagram.setAttribute('data-mxgraph', JSON.stringify(config));
      GraphViewer.createViewerForElement(diagram, function () {
        if (!diagram.querySelector('svg')) {
          fail('This file is empty or not a draw.io diagram.');
          return;
        }
        tagToolbar();
        reportHeight();
      });
    })
    .catch(function (error) { fail(error.message || 'The diagram could not be shown.'); });

  new ResizeObserver(reportHeight).observe(document.documentElement);
}());
