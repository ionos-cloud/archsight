<script setup>
import { ref, watch, inject } from 'vue'
import { getInstance } from '../../api/client.js'
import InstanceDetail from './InstanceDetail.vue'
import ViewDetail from './ViewDetail.vue'
import AnalysisDetail from './AnalysisDetail.vue'
import ImportDetail from './ImportDetail.vue'

const props = defineProps({
  kind: String,
  instance: String,
})

const kinds = inject('kinds')
const data = ref(null)
const loading = ref(true)
const error = ref(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    data.value = await getInstance(props.kind, props.instance)
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

watch(() => [props.kind, props.instance], load, { immediate: true })

function kindMeta() {
  if (!kinds.value) return null
  return kinds.value.kinds.find(k => k.kind === props.kind)
}
</script>

<template>
  <article v-if="loading"><p>Loading...</p></article>
  <article v-else-if="error">
    <header><h2>Not Found</h2></header>
    <p>Instance <strong>{{ instance }}</strong> of kind <strong>{{ kind }}</strong> was not found.</p>
  </article>
  <template v-else-if="data">
    <ViewDetail v-if="kind === 'View'" :data="data" :kind-meta="kindMeta()" />
    <AnalysisDetail v-else-if="kind === 'Analysis'" :data="data" :kind-meta="kindMeta()" />
    <ImportDetail v-else-if="kind === 'Import'" :data="data" :kind-meta="kindMeta()" />
    <InstanceDetail v-else :data="data" :kind="kind" :kind-meta="kindMeta()" />
  </template>
</template>
