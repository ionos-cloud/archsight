<script setup>
import { ref, watch, onUnmounted, nextTick } from 'vue'
import { getKindDot } from '../../api/client.js'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'

// The resources of a kind and the relations between them (a team's sub-teams, a service's dependencies on other
// services); resources without such a relation are only in the list
const props = defineProps({
  kind: String,
  total: Number,
})

const svgHtml = ref('')
const nodeCount = ref(0)
const loading = ref(true)
const graphBox = ref(null)
const graphEl = ref(null)
let panZoom = null

async function load() {
  loading.value = true
  panZoom?.destroy()
  panZoom = null
  const dot = await getKindDot(props.kind)
  svgHtml.value = dot ? await renderDot(dot) : ''
  nodeCount.value = (svgHtml.value.match(/class="node\b/g) || []).length
  loading.value = false
  await nextTick()
  const svg = graphEl.value?.querySelector('svg')
  if (svg) panZoom = initSvgPanZoom(svg, graphEl.value, { fullscreenTarget: graphBox.value })
}

watch(() => props.kind, load, { immediate: true })
onUnmounted(() => { panZoom?.destroy() })
</script>

<template>
  <p v-if="loading">Loading graph...</p>
  <p v-else-if="!nodeCount" class="kind-graph-note">No relations between {{ kind }} resources.</p>
  <template v-else>
    <p v-if="total > nodeCount" class="kind-graph-note">
      {{ nodeCount }} of {{ total }} resources are related to each other; the list shows all of them.
    </p>
    <div ref="graphBox" class="graph-container">
      <div id="graphviz" ref="graphEl" v-html="svgHtml"></div>
    </div>
  </template>
</template>

<style scoped>
.kind-graph-note {
  color: var(--pico-muted-color);
  font-size: var(--fs-sm);
}

.graph-container {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--pico-muted-border-color);
  border-radius: 4px;
  background-color: var(--pico-card-background-color);
  min-height: 150px; /* pan-zoom sets the height that fits the graph */
}

#graphviz {
  width: 100%;
  height: 100%;
}

:deep(#graphviz svg) {
  display: block;
}
</style>
