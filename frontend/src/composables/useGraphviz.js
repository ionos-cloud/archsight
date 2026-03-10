import graphCss from '../css/graph.css?raw'

let graphvizModule = null

async function ensureGraphviz() {
  if (graphvizModule) return graphvizModule
  const { Graphviz } = await import('@hpcc-js/wasm/graphviz')
  graphvizModule = await Graphviz.load()
  return graphvizModule
}

export async function renderDot(dot) {
  const gv = await ensureGraphviz()
  let svg = gv.layout(dot, 'svg', 'dot')

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
