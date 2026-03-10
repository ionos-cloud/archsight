import { initSvgPanZoom } from './usePanZoom.js'

let mermaidModule = null
let darkModeListenerAdded = false

function getTheme() {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'
}

async function ensureMermaid() {
  if (mermaidModule) return mermaidModule
  const mod = await import('mermaid')
  mermaidModule = mod.default
  mermaidModule.initialize({ startOnLoad: false, theme: getTheme() })
  setupDarkModeListener()
  return mermaidModule
}

function initPanZoomAll(container) {
  container.querySelectorAll('.mermaid svg').forEach(svg => {
    if (svg.hasAttribute('data-panzoom-init')) return
    svg.setAttribute('data-panzoom-init', 'true')
    const parent = svg.parentElement
    initSvgPanZoom(svg, parent)
  })
}

function setupDarkModeListener() {
  if (darkModeListenerAdded) return
  darkModeListenerAdded = true
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', async () => {
    if (!mermaidModule) return
    mermaidModule.initialize({ startOnLoad: false, theme: getTheme() })
    document.querySelectorAll('.mermaid[data-mermaid-source]').forEach(el => {
      el.removeAttribute('data-processed')
      el.innerHTML = el.getAttribute('data-mermaid-source')
    })
    await mermaidModule.run()
    document.querySelectorAll('.mermaid').forEach(el => {
      el.querySelectorAll('svg').forEach(svg => svg.removeAttribute('data-panzoom-init'))
      initPanZoomAll(el.parentElement || el)
    })
  })
}

export async function renderMermaidIn(container) {
  const codeBlocks = container.querySelectorAll('pre > code.language-mermaid')
  if (codeBlocks.length === 0) return

  const mm = await ensureMermaid()

  codeBlocks.forEach(code => {
    const pre = code.parentElement
    const div = document.createElement('div')
    div.className = 'mermaid'
    div.setAttribute('data-mermaid-source', code.textContent)
    div.textContent = code.textContent
    pre.parentElement.replaceChild(div, pre)
  })

  await mm.run()
  initPanZoomAll(container)
}
