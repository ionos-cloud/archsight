<script setup>
import { ref, computed, watch, inject } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getKindInstances } from '../../api/client.js'
import ResourceList from './ResourceList.vue'
import KindGraph from './KindGraph.vue'

const PAGE_SIZE = 100

const props = defineProps({
  kind: String,
})

const route = useRoute()
const router = useRouter()
const kinds = inject('kinds')
const instances = ref([])
const total = ref(0)
const loading = ref(true)
const loadingMore = ref(false)
const kindMeta = ref(null)
let offset = 0

async function load() {
  loading.value = true
  offset = 0
  try {
    const result = await getKindInstances(props.kind, { limit: PAGE_SIZE, offset: 0, output: 'brief' })
    // a renamed kind opened under its old name (an old link): carry on under the current name
    if (result.kind && result.kind !== props.kind) router.replace({ name: 'kind', params: { kind: result.kind } })
    instances.value = result.instances || []
    total.value = result.total || 0
    offset = instances.value.length
  } catch {
    instances.value = []
    total.value = 0
  }
  if (kinds.value) {
    kindMeta.value = kinds.value.kinds.find(k => k.kind === props.kind)
  }
  loading.value = false
}

async function loadMore() {
  if (loadingMore.value || offset >= total.value) return
  loadingMore.value = true
  try {
    const result = await getKindInstances(props.kind, { limit: PAGE_SIZE, offset, output: 'brief' })
    const items = result.instances || []
    instances.value = [...instances.value, ...items]
    offset += items.length
  } catch { /* ignore */ }
  loadingMore.value = false
}

watch(() => props.kind, load, { immediate: true })

// A kind whose resources relate to each other (teams of teams, services on services) can also be shown as a graph;
// the choice is in the URL (?view=graph), so it can be linked and survives a reload
const hasGraph = computed(() => !!kindMeta.value?.self_relations)
const showGraph = computed(() => hasGraph.value && route.query.view === 'graph')

function setView(view) {
  router.replace({ query: { ...route.query, view: view === 'graph' ? 'graph' : undefined } })
}

function kindSnake(kind) {
  return kind.replace(/([a-z])([A-Z])/g, '$1_$2').toLowerCase()
}
</script>

<template>
  <article v-if="!loading">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        {{ kind }}
      </h2>
      <div class="header-actions">
        <div v-if="hasGraph" class="kind-view" role="group" aria-label="Show as">
          <button type="button" :class="{ outline: showGraph, secondary: showGraph }" :aria-pressed="!showGraph"
                  aria-label="List" title="List of all resources" @click="setView('list')"><i class="iconoir-list"></i></button>
          <button type="button" :class="{ outline: !showGraph, secondary: !showGraph }" :aria-pressed="showGraph"
                  aria-label="Graph" :title="`Graph of the relations between ${kind} resources`"
                  @click="setView('graph')"><i class="iconoir-network"></i></button>
        </div>
        <router-link class="kind-help" :to="{ name: 'doc', params: { filename: 'resources/' + kindSnake(kind) } }" title="Documentation">
          <i class="iconoir-help-circle"></i>
        </router-link>
      </div>
    </header>
    <KindGraph v-if="showGraph" :kind="kind" :total="total" />
    <ResourceList v-else :instances="instances" :omit-kind="true" :total="total" :loading-more="loadingMore" @load-more="loadMore" />
  </article>
  <article v-else><p>Loading...</p></article>
</template>

<style scoped>
.header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.kind-view[role="group"] {
  display: inline-flex;
  width: fit-content;
  margin: 0;
}

.kind-view button {
  flex: 0 0 auto;
  width: auto;
  margin-bottom: 0;
  padding: 0.15rem 0.6rem;
  font-size: var(--fs-sm);
}
</style>
