<script setup>
import { ref, watch, inject } from 'vue'
import { getKindInstances } from '../../api/client.js'
import ResourceList from './ResourceList.vue'

const PAGE_SIZE = 100

const props = defineProps({
  kind: String,
})

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
        <router-link class="kind-help" :to="{ name: 'doc', params: { filename: 'resources/' + kindSnake(kind) } }" title="Documentation">
          <i class="iconoir-help-circle"></i>
        </router-link>
      </div>
    </header>
    <ResourceList :instances="instances" :omit-kind="true" :total="total" :loading-more="loadingMore" @load-more="loadMore" />
  </article>
  <article v-else><p>Loading...</p></article>
</template>
