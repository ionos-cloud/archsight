// draw.io diagrams in rendered markdown. The server turns `![](x.drawio)` into a placeholder
// (<span class="drawio-diagram" data-drawio-src="/api/v1/assets/...">) and this turns each one into the
// official draw.io viewer, read-only, in an iframe. The viewer is served by Archsight itself
// (public/vendor/drawio) with a policy that blocks every request to another host.

const VIEWER = '/vendor/drawio/viewer.html'
const CHANNEL = 'archsight-drawio'
const INITIAL_HEIGHT = 240
const MAX_HEIGHT = 4000

let listening = false

function frameFor(source) {
  return [...document.querySelectorAll('iframe.drawio-frame')].find((frame) => frame.contentWindow === source)
}

function showError(frame, message) {
  const box = document.createElement('div')
  box.className = 'drawio-error'
  box.setAttribute('role', 'alert')
  box.textContent = message
  frame.replaceWith(box)
}

function onMessage(event) {
  const data = event.data
  if (event.origin !== window.location.origin || !data || data.channel !== CHANNEL) return
  const frame = frameFor(event.source)
  if (!frame) return
  if (data.type === 'size' && Number.isFinite(data.height)) {
    frame.style.height = `${Math.min(Math.ceil(data.height), MAX_HEIGHT)}px`
  } else if (data.type === 'error') {
    showError(frame, data.message || 'The diagram could not be shown.')
  }
}

function createFrame(src, title) {
  const frame = document.createElement('iframe')
  frame.className = 'drawio-frame'
  frame.src = `${VIEWER}?src=${encodeURIComponent(src)}`
  frame.title = title || 'draw.io diagram'
  frame.loading = 'lazy'
  frame.referrerPolicy = 'no-referrer'
  // same origin so the viewer can read the diagram from the assets API; its own page policy keeps it
  // from talking to anybody else
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin')
  frame.style.height = `${INITIAL_HEIGHT}px`
  return frame
}

function openLink(src) {
  const link = document.createElement('a')
  link.className = 'drawio-open'
  link.href = src
  link.target = '_blank'
  link.rel = 'noopener'
  link.textContent = 'Open the .drawio file'
  return link
}

export function renderDrawioIn(container) {
  if (!container) return
  if (!listening) {
    window.addEventListener('message', onMessage)
    listening = true
  }
  container.querySelectorAll('.drawio-diagram[data-drawio-src]:not([data-drawio-ready])').forEach((element) => {
    const src = element.dataset.drawioSrc
    element.dataset.drawioReady = 'true'
    element.replaceChildren(createFrame(src, element.dataset.drawioTitle), openLink(src))
  })
}
