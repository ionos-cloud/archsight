// svg-pan-zoom fits a picture to the size of the screen with a transform and drops the SVG's viewBox, so on paper
// (a different width) the picture is cut off. For the time of printing every pan/zoom SVG gets a viewBox around its
// content; print.css removes the transform and sizes the SVG to the page. Call once (main.js).
const PADDING = 20

export function usePrintFit() {
  const saved = new Map() // svg -> its viewBox attribute before printing (null = none)

  window.addEventListener('beforeprint', () => {
    document.querySelectorAll('svg').forEach((svg) => {
      const viewport = svg.querySelector(':scope > .svg-pan-zoom_viewport')
      if (!viewport) return
      const box = viewport.getBBox()
      saved.set(svg, svg.getAttribute('viewBox'))
      svg.setAttribute(
        'viewBox',
        `${box.x - PADDING} ${box.y - PADDING} ${box.width + PADDING * 2} ${box.height + PADDING * 2}`,
      )
    })
  })

  window.addEventListener('afterprint', () => {
    saved.forEach((viewBox, svg) => {
      if (viewBox === null) svg.removeAttribute('viewBox')
      else svg.setAttribute('viewBox', viewBox)
    })
    saved.clear()
  })
}
