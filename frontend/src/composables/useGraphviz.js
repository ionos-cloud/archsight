import graphCss from '../css/graph.css?raw'

let worker = null
let nextId = 0
const pending = new Map()

function failAll(message) {
  for (const { reject } of pending.values()) reject(new Error(message))
  pending.clear()
  worker?.terminate()
  worker = null
}

function ensureWorker() {
  if (worker) return worker
  worker = new Worker(new URL('./graphviz.worker.js', import.meta.url), { type: 'module' })
  worker.onmessage = ({ data: { id, svg, error } }) => {
    const request = pending.get(id)
    if (!request) return
    pending.delete(id)
    if (error) request.reject(new Error(error))
    else request.resolve(svg)
  }
  worker.onerror = (event) => failAll(event.message || 'Graph layout failed')
  return worker
}

function layout(dot) {
  return new Promise((resolve, reject) => {
    const id = nextId++
    pending.set(id, { resolve, reject })
    ensureWorker().postMessage({ id, dot })
  })
}

export async function renderDot(dot) {
  let svg = await layout(dot)

  // Remove fixed width/height pt attributes from <svg> tag
  svg = svg.replace(/<svg width="[^"]*pt" height="[^"]*pt"/, '<svg')
  // Remove white background polygon
  svg = svg.replace(/<polygon fill="white"[^>]*\/>/, '')
  // Replace fill="white" with fill="none"
  svg = svg.replace(/fill="white"/g, 'fill="none"')

  // Inject graph CSS as inline <style> element
  const parser = new DOMParser()
  const doc = parser.parseFromString(svg, 'image/svg+xml')
  const svgEl = doc.querySelector('svg')

  const style = document.createElementNS('http://www.w3.org/2000/svg', 'style')
  style.textContent = graphCss
  svgEl.insertBefore(style, svgEl.firstChild)

  return svgEl.outerHTML
}
