<script setup>
import { ref, onMounted, onUnmounted, nextTick, watch } from 'vue'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'

const props = defineProps({ dot: String })
const svgHtml = ref('')
const loading = ref(true)
const error = ref(null)
const graphEl = ref(null)
let panZoom = null

async function render(dot) {
  if (!dot) { loading.value = false; return }
  panZoom?.destroy()
  panZoom = null
  loading.value = true
  error.value = null
  try {
    svgHtml.value = await renderDot(dot)
  } catch (e) {
    error.value = e?.message || 'Failed to render module graph'
    svgHtml.value = ''
  } finally {
    loading.value = false
    await nextTick()
    if (graphEl.value) {
      const svg = graphEl.value.querySelector('svg')
      if (svg) panZoom = initSvgPanZoom(svg, graphEl.value)
    }
  }
}

onMounted(() => render(props.dot))
watch(() => props.dot, render)
onUnmounted(() => { panZoom?.destroy() })
</script>

<template>
  <article>
    <header><h2>Module Structure</h2></header>
    <div v-if="loading"><p>Loading graph...</p></div>
    <p v-else-if="error" class="graph-error"><i class="iconoir-warning-triangle"></i> {{ error }}</p>
    <div v-else-if="svgHtml" class="graph-container">
      <div ref="graphEl" class="canvas" v-html="svgHtml"></div>
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

.canvas {
  width: 100%;
  height: 100%;
}

:deep(.canvas svg) {
  display: block;
}

.graph-error {
  color: var(--del-color);
  padding: 0.5rem 0;
}
</style>
