<script setup>
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { search } from '../../api/client.js'
import ResourceList from './ResourceList.vue'

const PAGE_SIZE = 100

const route = useRoute()
const results = ref([])
const total = ref(0)
const queryTime = ref(0)
const queryStr = ref('')
const kindFilter = ref(null)
const loading = ref(false)
const loadingMore = ref(false)
const error = ref(null)
let offset = 0

async function doSearch() {
  const q = route.query.q
  kindFilter.value = route.query.kind || null
  if (!q) { results.value = []; total.value = 0; return }
  queryStr.value = q
  loading.value = true
  error.value = null
  offset = 0
  try {
    const data = await search(q, { limit: PAGE_SIZE, offset: 0, output: 'brief' })
    results.value = data.instances || []
    total.value = data.total || 0
    queryTime.value = data.query_time_ms || 0
    offset = results.value.length
  } catch (e) {
    error.value = e.message
    results.value = []
  } finally {
    loading.value = false
  }
}

async function loadMore() {
  if (loadingMore.value || offset >= total.value) return
  const q = route.query.q
  if (!q) return
  loadingMore.value = true
  try {
    const data = await search(q, { limit: PAGE_SIZE, offset, output: 'brief' })
    const items = data.instances || []
    results.value = [...results.value, ...items]
    offset += items.length
  } catch { /* ignore */ }
  loadingMore.value = false
}

watch(() => route.query.q, doSearch, { immediate: true })
</script>

<template>
  <div v-if="error" class="search-error">
    <div class="search-error-header">
      <i class="iconoir-warning-triangle"></i>
      Query Syntax Error
    </div>
    <div class="search-error-message">{{ error }}</div>
    <div class="search-error-query">Query: <code>{{ queryStr }}</code></div>
  </div>

  <article class="search-context">
    <header><h3>Search Query</h3></header>
    <div class="search-query-display">
      <p class="query-item">
        <span class="label">Query:</span>
        <code class="query-value">{{ queryStr }}</code>
      </p>
      <p v-if="kindFilter" class="query-item">
        <span class="label">Kind:</span>
        <code class="kind-value">{{ kindFilter }}</code>
      </p>
      <p v-if="!error" class="query-item">
        <span class="label">Results:</span>
        <span class="result-count">{{ total }} {{ total === 1 ? 'item' : 'items' }}</span>
      </p>
      <p class="query-item">
        <span class="label">Time:</span>
        <span class="search-time">{{ queryTime }} ms</span>
      </p>
    </div>
  </article>

  <article v-if="!error && !loading" class="search-results">
    <header><h3>Results</h3></header>
    <p v-if="!results.length"><em>No results found</em></p>
    <ResourceList v-else :instances="results" :omit-kind="!!kindFilter" :total="total" :loading-more="loadingMore" @load-more="loadMore" />
  </article>

  <article v-if="loading"><p>Searching...</p></article>
</template>

<style scoped>
.search-query-display {
  display: flex;
  flex-wrap: wrap;
  gap: 1.5rem;
  align-items: center;
  padding: 1rem 0;
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
  letter-spacing: 0.5px;
}

.query-item code {
  padding: 0.35rem 0.75rem;
  background-color: var(--code-background-color);
  border-radius: 6px;
  font-size: 0.95em;
  font-family: monospace;
  color: var(--color);
}

.query-value {
  word-break: break-word;
}

.kind-value {
  text-transform: capitalize;
}

.result-count {
  font-weight: 600;
  color: var(--color);
  font-size: 1em;
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

.search-error-header i {
  font-size: 1.2em;
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

.search-error-query {
  margin-top: 0.5rem;
  font-size: 0.85em;
  color: #7f1d1d;
}

.search-error-query code {
  background-color: #fef2f2;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
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
  .search-error-query {
    color: #fca5a5;
  }
  .search-error-query code {
    background-color: #7f1d1d;
  }
}
</style>
