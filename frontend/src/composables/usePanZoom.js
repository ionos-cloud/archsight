import svgPanZoom from 'svg-pan-zoom'

function createZoomControls(container, instance) {
  if (container.querySelector('.svg-zoom-controls')) return

  const controls = document.createElement('div')
  controls.className = 'svg-zoom-controls'
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
  `

  controls.querySelector('[data-action="zoom-in"]').addEventListener('click', () => instance.zoomIn())
  controls.querySelector('[data-action="zoom-out"]').addEventListener('click', () => instance.zoomOut())
  controls.querySelector('[data-action="reset"]').addEventListener('click', () => {
    instance.resetZoom()
    instance.resetPan()
    instance.fit()
    instance.center()
  })

  container.style.position = 'relative'
  container.appendChild(controls)
}

export function initSvgPanZoom(svg, container) {
  // Fix viewBox to include all content with padding
  const bbox = svg.getBBox()
  const padding = 20
  const viewBox = (bbox.x - padding) + ' ' + (bbox.y - padding) + ' ' +
                  (bbox.width + padding * 2) + ' ' + (bbox.height + padding * 2)
  svg.setAttribute('viewBox', viewBox)

  // Calculate ideal container height based on SVG content
  const contentWidth = bbox.width + padding * 2
  const contentHeight = bbox.height + padding * 2
  const containerWidth = container.clientWidth || 800
  const aspectRatio = contentHeight / contentWidth

  const idealHeight = Math.round(containerWidth * aspectRatio)
  const minHeight = 150
  const maxHeight = Math.round(window.innerHeight * 0.7)
  const finalHeight = Math.max(minHeight, Math.min(idealHeight + 60, maxHeight))

  container.style.height = finalHeight + 'px'

  // Remove fixed dimensions
  svg.removeAttribute('width')
  svg.removeAttribute('height')
  svg.removeAttribute('style')
  svg.style.cssText = 'max-width: none !important; width: 100%; height: 100%;'

  const instance = svgPanZoom(svg, {
    zoomEnabled: true,
    controlIconsEnabled: false,
    fit: true,
    contain: false,
    center: true,
    minZoom: 0.1,
    maxZoom: 10,
    zoomScaleSensitivity: 0.3,
  })

  createZoomControls(container, instance)

  const resizeHandler = () => {
    instance.resize()
    instance.fit()
    instance.center()
  }
  window.addEventListener('resize', resizeHandler)

  setTimeout(resizeHandler, 100)

  return { instance, destroy: () => {
    window.removeEventListener('resize', resizeHandler)
    instance.destroy()
  }}
}
