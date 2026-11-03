import { Graphviz } from '@hpcc-js/wasm/graphviz'

// Lays out DOT with the wasm Graphviz off the main thread: a big graph takes seconds and must not freeze the page.
let ready = null

self.onmessage = async ({ data: { id, dot } }) => {
  try {
    ready ||= Graphviz.load()
    const gv = await ready
    self.postMessage({ id, svg: gv.layout(dot, 'svg', 'dot') })
  } catch (e) {
    self.postMessage({ id, error: e?.message || String(e) })
  }
}
