// "Archsight" at the bottom left of every printed page. Chromium 131 and later draws it from the page's margin box
// (`@page { @bottom-left }` in print.css). Firefox and Safari do not support margin boxes, so there it is an element
// fixed to the page, which those browsers repeat on every printed page. It exists only while printing. Call once
// (main.js).
function supportsMarginBoxes() {
  // only Chromium browsers have userAgentData; the version is that of the engine
  const chromium = navigator.userAgentData?.brands?.find((brand) => brand.brand === 'Chromium')
  return !!chromium && Number(chromium.version) >= 131
}

export function usePrintWatermark() {
  let element = null

  window.addEventListener('beforeprint', () => {
    if (element || supportsMarginBoxes()) return
    element = document.createElement('div')
    element.className = 'print-watermark'
    element.setAttribute('aria-hidden', 'true')
    element.textContent = 'Archsight'
    document.body.appendChild(element)
  })

  window.addEventListener('afterprint', () => {
    element?.remove()
    element = null
  })
}
