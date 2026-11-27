<script setup>
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { search } from '../../api/client.js'
import { scopedQuery } from '../../composables/useSearchScope.js'
import ResourceList from './ResourceList.vue'
import KindFacets from '../search/KindFacets.vue'
import QueryError from '../search/QueryError.vue'
import SearchHints from '../search/SearchHints.vue'

const PAGE_SIZE = 100

const route = useRoute()
const router = useRouter()
const results = ref([])
const total = ref(0)
const byKind = ref({})
const queryTime = ref(0)
const queryStr = ref('')
const effectiveQuery = ref('')
const scope = ref('kinds')
const kindFilter = ref(null)
const ranked = ref(false) // the query searches text: hits can be ordered by relevance
const sortBy = computed(() => (route.query.sort === 'name' ? 'name' : 'relevance'))
const loading = ref(false)
const loadingMore = ref(false)
const error = ref(null)
const moreError = ref(false)
let offset = 0
let request = 0 // answers that arrive after a newer search was started are dropped

const hasQuery = computed(() => !!queryStr.value)
// with a single kind there is nothing to choose, unless a kind is selected (then "All" must stay reachable)
const showFacets = computed(() => Object.keys(byKind.value).length > 1 || !!kindFilter.value)
const stale = computed(() => loading.value || !!error.value)
const countText = computed(() => {
  const noun = total.value === 1 ? 'result' : 'results'
  return kindFilter.value ? `${total.value} ${noun} in ${kindFilter.value}` : `${total.value} ${noun}`
})

async function doSearch() {
  const q = route.query.q
  kindFilter.value = route.query.kind || null
  scope.value = route.query.scope === 'pages' ? 'pages' : 'kinds'
  if (!q) {
    request++
    results.value = []; total.value = 0; byKind.value = {}
    queryStr.value = ''; effectiveQuery.value = ''
    error.value = null; loading.value = false
    return
  }
  queryStr.value = q
  effectiveQuery.value = scopedQuery(q, scope.value)
  const mine = ++request
  loading.value = true
  error.value = null
  moreError.value = false
  try {
    // the previous hits stay on screen (dimmed) until the new ones are here
    const data = await search(effectiveQuery.value, { limit: PAGE_SIZE, offset: 0, output: 'brief', kind: kindFilter.value, fulltext: true, sort: route.query.sort === 'name' ? 'name' : null })
    if (mine !== request) return
    results.value = data.instances || []
    total.value = data.total || 0
    byKind.value = data.by_kind || {}
    ranked.value = !!data.ranked
    queryTime.value = data.query_time_ms || 0
    offset = results.value.length
  } catch (e) {
    if (mine !== request) return
    // a query that does not parse (often only while typing) keeps the last hits visible
    error.value = e.message
  } finally {
    if (mine === request) loading.value = false
  }
}

async function loadMore() {
  if (loadingMore.value || offset >= total.value || !queryStr.value) return
  loadingMore.value = true
  moreError.value = false
  const mine = request
  try {
    const data = await search(effectiveQuery.value, { limit: PAGE_SIZE, offset, output: 'brief', kind: kindFilter.value, fulltext: true, sort: route.query.sort === 'name' ? 'name' : null })
    if (mine !== request) return
    const items = data.instances || []
    results.value = [...results.value, ...items]
    offset += items.length
  } catch {
    moreError.value = true
  } finally {
    loadingMore.value = false
  }
}

function setSort(value) {
  router.replace({ query: { ...route.query, sort: value === 'name' ? 'name' : undefined } })
}

watch(() => [route.query.q, route.query.scope, route.query.kind, route.query.sort], doSearch, { immediate: true })
</script>

<template>
  <article class="search-page">
    <!-- not aria-busy: Pico draws a spinner for it, which pushes the whole page down while a search runs -->
    <span class="sr-only" role="status" aria-live="polite">{{ loading ? 'Searching' : '' }}</span>
    <header>
      <h2><i class="iconoir-search" aria-hidden="true"></i> Search</h2>
      <div class="header-actions">
        <router-link class="search-syntax" to="/doc/search" title="Query syntax">
          <i class="iconoir-help-circle" aria-hidden="true"></i>
        </router-link>
      </div>
    </header>

    <SearchHints v-if="!hasQuery" mode="intro" :scope="scope" />

    <template v-else>
      <KindFacets v-if="showFacets" :by-kind="byKind" :selected="kindFilter" />

      <QueryError v-if="error" :message="error" />

      <p v-if="!error && results.length" class="search-summary">
        {{ countText }}
        <span class="search-meta">{{ queryTime }} ms</span>
        <!-- no role="group": Pico turns it into a full-width button bar -->
        <span v-if="ranked" class="search-sort">
          <span class="sr-only">Order:</span>
          <button type="button" :aria-pressed="sortBy === 'relevance'" @click="setSort('relevance')">Best matches</button>
          <button type="button" :aria-pressed="sortBy === 'name'" @click="setSort('name')">Name</button>
        </span>
        <span v-if="scope === 'pages' && effectiveQuery !== queryStr" class="search-meta">
          searched as <code>{{ effectiveQuery }}</code>
        </span>
      </p>

      <div :class="{ stale }">
        <ResourceList
          v-if="results.length"
          rows
          :instances="results"
          :omit-kind="!!kindFilter"
          :page-links="scope === 'pages'"
          :total="total"
          :loading-more="loadingMore"
          @load-more="loadMore"
        />
        <p v-if="moreError" class="more-error">
          Could not load more results.
          <button type="button" class="more-retry" @click="loadMore">Try again</button>
        </p>
      </div>

      <SearchHints v-if="!loading && !error && !results.length" mode="empty" :query="queryStr" :scope="scope" />
    </template>
  </article>
</template>

<style scoped>
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}

.search-syntax {
  display: inline-flex;
  align-items: center;
  color: var(--pico-muted-color);
}

.search-syntax:hover {
  color: var(--pico-primary);
}

.search-summary {
  margin: 0 0 0.25rem;
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
}

.search-meta {
  margin-left: 0.75rem;
}

.search-sort {
  margin-left: 0.75rem;
}

.search-summary .search-sort button {
  display: inline;
  width: auto;
  margin: 0 0.15rem 0 0;
  padding: 0.05rem 0.45rem;
  border: 1px solid transparent;
  border-radius: 4px;
  background: none;
  color: var(--pico-muted-color);
  font-size: inherit;
  line-height: inherit;
  box-shadow: none;
  cursor: pointer;
}

/* Pico redefines --pico-color inside a button (white), so the pressed one takes the primary colour */
.search-summary .search-sort button[aria-pressed='true'] {
  border-color: var(--line);
  background-color: var(--tint);
  color: var(--pico-primary);
}

.search-summary code {
  font-size: var(--fs-xs);
}

/* the previous hits stay while a new search runs or its query is wrong */
.stale {
  opacity: 0.5;
  transition: opacity 0.15s ease;
}

.more-error {
  margin: 0.5rem 0 0;
  font-size: var(--fs-xs);
  color: var(--pico-del-color);
}

.more-retry {
  display: inline;
  width: auto;
  margin: 0 0 0 0.5rem;
  padding: 0;
  border: 0;
  background: none;
  color: var(--pico-primary);
  font-size: inherit;
  text-decoration: underline;
  cursor: pointer;
}
</style>
