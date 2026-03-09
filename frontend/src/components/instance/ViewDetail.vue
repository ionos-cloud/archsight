<script setup>
import { ref, computed, watch } from 'vue'
import { search } from '../../api/client.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import ResourceList from './ResourceList.vue'

const props = defineProps({
  data: Object,
  kindMeta: Object,
})

const annotations = computed(() => props.data.metadata?.annotations || {})
const viewQuery = computed(() => annotations.value['view/query'])
const viewDescription = computed(() => annotations.value['architecture/description'])
const viewType = computed(() => annotations.value['view/type'] || 'list:name+kind')
const showKind = computed(() => viewType.value === 'list:name+kind')

const viewFields = computed(() => {
  const raw = annotations.value['view/fields'] || ''
  return raw.split(',').map(s => s.trim()).filter(Boolean)
})

const viewSortFields = computed(() => {
  const raw = annotations.value['view/sort'] || ''
  return raw.split(',').map(s => s.trim()).filter(Boolean)
})

const PAGE_SIZE = 100

const descEl = ref(null)
useInternalLinks(descEl)
const rawResults = ref([])
const total = ref(0)
const queryTime = ref(0)
const loading = ref(false)
const loadingMore = ref(false)
const error = ref(null)
let offset = 0

function sortInstances(instances, sortFields) {
  if (!sortFields.length) return instances
  return [...instances].sort((a, b) => {
    for (const field of sortFields) {
      const desc = field.startsWith('-')
      const key = desc ? field.slice(1) : field
      const aVal = a.annotations?.[key] ?? ''
      const bVal = b.annotations?.[key] ?? ''
      const cmp = String(aVal).localeCompare(String(bVal), undefined, { numeric: true })
      if (cmp !== 0) return desc ? -cmp : cmp
    }
    return 0
  })
}

const results = computed(() => sortInstances(rawResults.value, viewSortFields.value))

async function executeQuery() {
  if (!viewQuery.value) return
  loading.value = true
  error.value = null
  offset = 0
  try {
    const outputLevel = viewFields.value.length ? 'annotations' : 'brief'
    const data = await search(viewQuery.value, { limit: PAGE_SIZE, offset: 0, output: outputLevel })
    rawResults.value = data.instances || []
    total.value = data.total || 0
    queryTime.value = data.query_time_ms || 0
    offset = rawResults.value.length
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function loadMore() {
  if (loadingMore.value || offset >= total.value || !viewQuery.value) return
  loadingMore.value = true
  try {
    const outputLevel = viewFields.value.length ? 'annotations' : 'brief'
    const data = await search(viewQuery.value, { limit: PAGE_SIZE, offset, output: outputLevel })
    const items = data.instances || []
    rawResults.value = [...rawResults.value, ...items]
    offset += items.length
  } catch { /* ignore */ }
  loadingMore.value = false
}

watch(() => props.data, executeQuery, { immediate: true })
</script>

<template>
  <article class="view-header">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        {{ data.name }}
      </h2>
    </header>
    <div ref="descEl" v-if="viewDescription" class="view-description" v-html="viewDescription"></div>
    <div v-if="viewQuery" class="view-query-display">
      <p class="query-item">
        <span class="label">Query:</span>
        <code class="query-value">{{ viewQuery }}</code>
      </p>
    </div>
  </article>

  <div v-if="error" class="search-error">
    <div class="search-error-header"><i class="iconoir-warning-triangle"></i> Query Error</div>
    <div class="search-error-message">{{ error }}</div>
  </div>

  <article v-if="!loading && viewQuery && !error" class="view-results">
    <header>
      <h3>Results</h3>
      <span class="view-result-meta">{{ total }} {{ total === 1 ? 'item' : 'items' }} in {{ queryTime }} ms</span>
    </header>
    <ResourceList
      :instances="results"
      :omit-kind="!showKind"
      :fields="viewFields.length ? viewFields : null"
      :total="total"
      :loading-more="loadingMore"
      @load-more="loadMore"
    />
  </article>

  <article v-if="!viewQuery">
    <p class="view-empty-state"><em>No query defined</em></p>
  </article>
</template>

<style scoped>
.view-header {
  margin-bottom: 0.75rem;
}

.view-header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.view-header h2 i {
  color: var(--primary);
}

.view-description {
  margin-top: 0.75rem;
  padding: 0.75rem;
  background-color: var(--card-background-color);
  border-radius: 8px;
  border: 1px solid var(--muted-border-color);
}

.view-query-display {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: center;
  padding: 0.5rem 0;
}

.query-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  padding: 0;
}

.query-item .label {
  font-weight: 600;
  color: var(--muted-color);
  text-transform: uppercase;
  font-size: 0.85em;
}

.query-item code {
  padding: 0.25rem 0.5rem;
  background-color: var(--code-background-color);
  border-radius: 4px;
}

.view-result-meta {
  font-size: 0.9em;
  color: var(--muted-color);
  margin-left: 1rem;
}

.view-empty-state {
  padding: 1.5rem;
  text-align: center;
  color: var(--muted-color);
}

.search-error {
  padding: 1rem;
  background-color: #fee2e2;
  border: 1px solid #fecaca;
  border-radius: 8px;
  margin-bottom: 1rem;
}

.search-error-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
  color: #991b1b;
  font-weight: 600;
}

.search-error-message {
  font-family: monospace;
  font-size: 0.95em;
  color: #991b1b;
  background-color: #fef2f2;
  padding: 0.75rem;
  border-radius: 4px;
  overflow-x: auto;
  white-space: pre-wrap;
  word-break: break-word;
}

@media (prefers-color-scheme: dark) {
  .search-error {
    background-color: #450a0a;
    border-color: #7f1d1d;
  }
  .search-error-header {
    color: #fca5a5;
  }
  .search-error-message {
    color: #fecaca;
    background-color: #7f1d1d;
  }
}
</style>
