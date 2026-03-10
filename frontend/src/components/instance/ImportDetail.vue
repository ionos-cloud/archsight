<script setup>
import { ref, computed, onMounted, onUnmounted, nextTick } from 'vue'
import { getInstanceDot } from '../../api/client.js'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import RelationsGrid from './RelationsGrid.vue'

const props = defineProps({
  data: Object,
  kindMeta: Object,
})

const svgHtml = ref('')
const graphEl = ref(null)
let panZoom = null
const descEl = ref(null)
useInternalLinks(descEl)
const annotations = computed(() => props.data.metadata?.annotations || {})

const handler = computed(() => annotations.value['import/handler'])
const enabled = computed(() => annotations.value['import/enabled'] !== 'false')
const cacheTime = computed(() => annotations.value['import/cacheTime'])
const priority = computed(() => annotations.value['import/priority'])
const outputPath = computed(() => annotations.value['import/outputPath'])
const description = computed(() => annotations.value['architecture/description'])

const configEntries = computed(() => {
  return Object.entries(annotations.value)
    .filter(([k]) => k.startsWith('import/config/'))
    .map(([k, v]) => [k.replace('import/config/', ''), v])
})

const relationCount = computed(() => {
  const r = props.data.relations || {}
  return Object.values(r).reduce((sum, kinds) => {
    if (typeof kinds === 'object') {
      return sum + Object.values(kinds).reduce((s, arr) => s + (Array.isArray(arr) ? arr.length : 0), 0)
    }
    return sum
  }, 0)
})

const hasOutgoingRelations = computed(() => Object.keys(props.data.relations || {}).length > 0)
const hasRelations = computed(() => {
  const refs = props.data.references || {}
  return hasOutgoingRelations.value || Object.keys(refs).length > 0
})

const graphTooLarge = computed(() => relationCount.value >= 50)

onMounted(async () => {
  if (hasOutgoingRelations.value && !graphTooLarge.value) {
    const dot = await getInstanceDot('Import', props.data.name)
    svgHtml.value = dot ? await renderDot(dot) : ''
    await nextTick()
    initPanZoomOnGraph()
  }
})

onUnmounted(() => { panZoom?.destroy() })

function initPanZoomOnGraph() {
  if (!graphEl.value) return
  const svg = graphEl.value.querySelector('svg')
  if (!svg) return
  panZoom = initSvgPanZoom(svg, graphEl.value)
}

function isUrl(v) {
  if (typeof v !== 'string') return false
  return v.startsWith('http') || v.startsWith('git@') || v.startsWith('file://')
}
</script>

<template>
  <article class="import-header">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        <div class="instance-title-text">
          <span class="instance-name">{{ data.name }}</span>
          <span class="instance-kind-subtitle">Import</span>
        </div>
      </h2>
      <div class="header-actions">
        <span v-if="handler" class="badge badge-primary">{{ handler }}</span>
        <span v-if="!enabled" class="badge badge-warning">Disabled</span>
        <router-link
          class="btn-header"
          :to="`/kinds/Import/instances/${data.name}/edit`"
          title="Edit this resource"
        >
          <i class="iconoir-edit-pencil"></i> Edit
        </router-link>
      </div>
    </header>

    <div ref="descEl" v-if="description" class="import-description" v-html="description"></div>

    <template v-if="hasRelations">
      <div v-if="hasOutgoingRelations && !graphTooLarge && svgHtml" class="graph-container">
        <div id="graphviz" ref="graphEl" class="canvas" v-html="svgHtml"></div>
      </div>
      <p v-else-if="graphTooLarge" class="graph-too-large">
        <i class="iconoir-warning-triangle"></i>
        Graph too large to display ({{ relationCount }} relations)
      </p>
      <p v-else-if="!hasOutgoingRelations" class="graph-too-large">
        <i class="iconoir-graph-up"></i> No outgoing dependencies — graph omitted
      </p>
    </template>
  </article>

  <article class="import-configuration">
    <header>
      <h3><i class="iconoir-settings"></i> Configuration</h3>
    </header>
    <div class="import-metadata">
      <span v-if="handler" class="import-meta-item">
        <i class="iconoir-code"></i> {{ handler }}
      </span>
      <span v-if="cacheTime" class="import-meta-item">
        <i class="iconoir-timer"></i> {{ cacheTime }}
      </span>
      <span v-if="priority" class="import-meta-item">
        <i class="iconoir-sort-down"></i> Priority: {{ priority }}
      </span>
      <span v-if="enabled" class="import-meta-item status-enabled">
        <i class="iconoir-check-circle"></i> Enabled
      </span>
      <span v-else class="import-meta-item status-disabled">
        <i class="iconoir-xmark-circle"></i> Disabled
      </span>
    </div>

    <div v-if="outputPath" class="import-output-path">
      <strong>Output:</strong>
      <code>{{ outputPath }}</code>
    </div>

    <details v-if="configEntries.length" class="import-config-section" open>
      <summary>
        <i class="iconoir-list"></i> Handler Settings
      </summary>
      <table class="import-config-table">
        <tbody>
          <tr v-for="[key, value] in configEntries" :key="key">
            <th scope="row">{{ key }}</th>
            <td>
              <code v-if="isUrl(value)">{{ value }}</code>
              <template v-else>{{ value }}</template>
            </td>
          </tr>
        </tbody>
      </table>
    </details>
  </article>

  <RelationsGrid :data="data" />
</template>

<style scoped>
.instance-title-text {
  display: flex;
  flex-direction: column;
  line-height: 1;
}

.instance-kind-subtitle {
  font-size: 0.4em;
  font-weight: 400;
  color: var(--muted-color);
  opacity: 0.7;
  margin-top: 0.1em;
}

.instance-name {
  font-weight: 600;
  font-size: 1em;
  color: var(--primary);
  text-decoration: none;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.btn-header {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.4rem 0.75rem;
  font-size: 0.9rem;
  color: var(--muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--border-radius);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-header:hover {
  color: var(--primary);
  border-color: var(--primary);
}

.import-header {
  margin-bottom: 0.75rem;
}

.import-header header {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
}

.import-header header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-right: auto;
}

.import-description {
  margin-top: 0.75rem;
  padding: 0.75rem;
  background-color: var(--card-background-color);
  border-radius: 8px;
  border: 1px solid var(--muted-border-color);
}

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

#graphviz {
  width: 100%;
  height: 100%;
}

:deep(#graphviz svg) {
  display: block;
}

.import-metadata {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  margin-bottom: 1rem;
}

.import-meta-item {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.9em;
  color: var(--muted-color);
  padding: 0.25rem 0.5rem;
  background-color: var(--code-background-color);
  border-radius: 4px;
}

.import-meta-item i { font-size: 1.1em; }
.import-meta-item.status-enabled { color: #10b981; }
.import-meta-item.status-disabled { color: #ef4444; }

.import-output-path {
  margin-bottom: 1rem;
  padding: 0.5rem 0.75rem;
  background-color: var(--code-background-color);
  border-radius: 4px;
}

.import-output-path code { margin-left: 0.5rem; }

.import-config-section {
  margin-top: 1rem;
  border: 1px solid var(--muted-border-color);
  border-radius: 8px;
  background-color: var(--card-background-color);
}

.import-config-section summary {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  cursor: pointer;
  font-weight: 600;
  color: var(--muted-color);
  user-select: none;
}

.import-config-section summary:hover { color: var(--color); }

.import-config-section summary::marker,
.import-config-section summary::-webkit-details-marker { display: none; }

.import-config-section summary::before {
  content: '\25B6';
  font-size: 0.7em;
  transition: transform 0.2s ease;
}

.import-config-section[open] summary::before { transform: rotate(90deg); }

.import-config-table {
  width: 100%;
  margin: 0;
  border-collapse: collapse;
}

.import-config-table th,
.import-config-table td {
  padding: 0.5rem 1rem;
  border-top: 1px solid var(--muted-border-color);
}

.import-config-table th {
  width: 30%;
  text-align: left;
  font-weight: 500;
  color: var(--muted-color);
}

.import-config-table code { word-break: break-all; }
</style>
