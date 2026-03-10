<script setup>
import { ref, onMounted, onUnmounted, nextTick } from 'vue'
import { getGlobalDot } from '../../api/client.js'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'

const svgHtml = ref('')
const loading = ref(true)
const graphEl = ref(null)
let panZoom = null

onMounted(async () => {
  const dot = await getGlobalDot()
  svgHtml.value = dot ? await renderDot(dot) : ''
  loading.value = false
  await nextTick()
  initPanZoomOnGraph()
})

onUnmounted(() => { panZoom?.destroy() })

function initPanZoomOnGraph() {
  if (!graphEl.value) return
  const svg = graphEl.value.querySelector('svg')
  if (!svg) return
  panZoom = initSvgPanZoom(svg, graphEl.value)
}
</script>

<template>
  <article>
    <header><h2>Architecture Overview</h2></header>
    <div v-if="loading"><p>Loading graph...</p></div>
    <div v-else class="graph-container graph-expand">
      <div id="graphviz" ref="graphEl" class="fullcanvas" v-html="svgHtml"></div>
    </div>
  </article>
</template>

<style scoped>
.graph-container {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--muted-border-color);
  border-radius: 4px;
  background-color: var(--card-background-color);
  height: auto;
  min-height: 150px;
  max-height: 70vh;
}

.graph-container.graph-expand {
  height: 85vh;
  max-height: none;
}

#graphviz {
  width: 100%;
  height: 100%;
}

:deep(#graphviz svg) {
  display: block;
}
</style>
