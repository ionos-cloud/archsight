// "Archsight" at the bottom left of every printed page: an element fixed to the page, which the browsers repeat on
// every printed page. It exists only while printing. Call once (main.js).
//
// It is an element and not the page's margin box (`@page { @bottom-left }`) because a margin box lives in the page
// margin, and the margins of a print are the user's choice: "None", "Minimum" or custom margins in the print dialog
// replace the `@page` margin, and the margin box has no room left. An element in the page area is always there.
export function usePrintWatermark() {
  let element = null

  window.addEventListener('beforeprint', () => {
    if (element) return
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
