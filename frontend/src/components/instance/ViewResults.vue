<script setup>
import { ref, computed, watch } from 'vue'
import { search } from '../../api/client.js'
import { fieldValue } from '../../composables/useFormatting.js'
import ResourceList from './ResourceList.vue'

// Runs a view's query and lists the result (the view page and page embeds). Loading is local: the parent
// renders at once and this shows a spinner until the result is there.
const props = defineProps({
  query: String,
  fields: { type: Array, default: () => [] },
  sort: { type: Array, default: () => [] },
  showKind: { type: Boolean, default: true },
  compact: { type: Boolean, default: false },
})

const emit = defineEmits(['loaded'])

const PAGE_SIZE = 100

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
      const aVal = fieldValue(a, key) ?? ''
      const bVal = fieldValue(b, key) ?? ''
      const cmp = String(aVal).localeCompare(String(bVal), undefined, { numeric: true })
      if (cmp !== 0) return desc ? -cmp : cmp
    }
    return 0
  })
}

const results = computed(() => sortInstances(rawResults.value, props.sort))
const outputLevel = computed(() => (props.fields.length ? 'annotations' : 'brief'))

async function executeQuery() {
  if (!props.query) return
  loading.value = true
  error.value = null
  offset = 0
  try {
    const data = await search(props.query, { limit: PAGE_SIZE, offset: 0, output: outputLevel.value })
    rawResults.value = data.instances || []
    total.value = data.total || 0
    queryTime.value = data.query_time_ms || 0
    offset = rawResults.value.length
    emit('loaded', { total: total.value })
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

async function loadMore() {
  if (loadingMore.value || offset >= total.value || !props.query) return
  loadingMore.value = true
  try {
    const data = await search(props.query, { limit: PAGE_SIZE, offset, output: outputLevel.value })
    const items = data.instances || []
    rawResults.value = [...rawResults.value, ...items]
    offset += items.length
  } catch { /* ignore */ }
  loadingMore.value = false
}

watch(() => [props.query, props.fields.join(',')], executeQuery, { immediate: true })
</script>

<template>
  <div v-if="error" class="search-error">
    <div class="search-error-header"><i class="iconoir-warning-triangle"></i> Query Error</div>
    <div class="search-error-message">{{ error }}</div>
  </div>

  <article v-else-if="loading" class="view-loading" aria-busy="true">
    <i class="iconoir-refresh spinning"></i> Running query...
  </article>

  <article v-else-if="query" class="view-results">
    <header v-if="!compact">
      <h3>Results</h3>
      <span class="view-result-meta">{{ total }} {{ total === 1 ? 'item' : 'items' }} in {{ queryTime }} ms</span>
    </header>
    <ResourceList
      :instances="results"
      :omit-kind="!showKind"
      :fields="fields.length ? fields : null"
      :total="total"
      :loading-more="loadingMore"
      @load-more="loadMore"
    />
  </article>
</template>

<style scoped>
.view-result-meta {
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
  margin-left: 1rem;
}

.view-loading {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--pico-muted-color);
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.spinning {
  animation: spin 1s linear infinite;
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
  font-family: var(--font-mono);
  font-size: var(--fs-sm);
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
