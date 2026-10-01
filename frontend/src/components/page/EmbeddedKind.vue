<script setup>
import { ref, computed, watch } from 'vue'
import { getInstance } from '../../api/client.js'
import { viewSpec } from '../../composables/useViewSpec.js'
import ViewResults from '../instance/ViewResults.vue'
import AnalysisResults from '../instance/AnalysisResults.vue'

// The live content of a View or Analysis inside a page (`![[View/Name]]`). The page is already on screen when
// this mounts; the resource, its query or script are loaded here, and a spinner shows until they are there.
const props = defineProps({
  kind: String,
  name: String,
})

const instance = ref(null)
const total = ref(null)
const analysis = ref(null) // { result, executing } of an embedded analysis
const analysisEl = ref(null)
const error = ref(null)

async function load() {
  instance.value = null
  total.value = null
  analysis.value = null
  error.value = null
  try {
    instance.value = await getInstance(props.kind, props.name)
  } catch (e) {
    error.value = e.message
  }
}
watch(() => [props.kind, props.name], load, { immediate: true })

const annotations = computed(() => instance.value?.metadata?.annotations || {})
const spec = computed(() => viewSpec(annotations.value))
// "Completed with findings 0.00s", for the line above the embedded analysis
const analysisStatus = computed(() => {
  const result = analysis.value?.result
  if (!result) return null
  const label = !result.success ? 'Failed' : result.has_findings ? 'Completed with findings' : 'Completed successfully'
  return { label: result.duration ? `${label} ${result.duration.toFixed(2)}s` : label }
})
const hasScript = computed(() => !!annotations.value['analysis/script'])
const icon = computed(() => (props.kind === 'View' ? 'iconoir-table-rows' : 'iconoir-play'))
</script>

<template>
  <div class="kind-embed-box">
    <p class="kind-embed-source">
      <i :class="icon"></i>
      <router-link :to="{ name: 'instance', params: { kind, instance: name } }" :title="`Open ${kind.toLowerCase()} ${name}`">{{ name }}</router-link>
      <span v-if="total != null" class="kind-embed-count">({{ total }} {{ total === 1 ? 'item' : 'items' }})</span>
      <template v-if="analysis">
        <span v-if="analysis.result" class="kind-embed-status" :class="{ failed: !analysis.result.success }">({{ analysisStatus.label }})</span>
        <span v-else-if="analysis.executing" class="kind-embed-status">(Running...)</span>
        <button class="kind-embed-rerun" :disabled="analysis.executing" title="Run the analysis again" aria-label="Run the analysis again" @click="analysisEl?.run()">
          <i class="iconoir-refresh" :class="{ spinning: analysis.executing }"></i>
        </button>
      </template>
    </p>

    <div v-if="error" class="kind-embed-error" role="alert">{{ error }}</div>
    <p v-else-if="!instance" class="kind-embed-loading" aria-busy="true">
      <i class="iconoir-refresh spinning"></i> Loading {{ kind.toLowerCase() }}...
    </p>
    <template v-else-if="kind === 'View'">
      <ViewResults v-if="spec.query" :query="spec.query" :fields="spec.fields" :sort="spec.sort" :show-kind="spec.showKind" compact @loaded="total = $event.total" />
      <p v-else class="kind-embed-empty">No query defined</p>
    </template>
    <template v-else-if="kind === 'Analysis'">
      <AnalysisResults v-if="hasScript" ref="analysisEl" :name="name" compact @state="analysis = $event" />
      <p v-else class="kind-embed-empty">No script defined for this analysis</p>
    </template>
  </div>
</template>

<style scoped>
.kind-embed-source {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin: 0 0 0.25rem;
  font-size: 0.8em;
  color: var(--muted-color);
}

.kind-embed-source a {
  color: inherit;
  text-decoration: none;
}

.kind-embed-source a:hover {
  color: var(--primary);
  text-decoration: underline;
}

.kind-embed-status.failed {
  color: #ef4444;
}

.kind-embed-rerun {
  font-size: inherit;
  line-height: 1;
  display: inline-flex;
  align-items: center;
  margin: 0;
  padding: 0 0.25rem;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
}

.kind-embed-rerun i {
  font-size: 1.1em;
}

.kind-embed-rerun:hover:not(:disabled) {
  color: var(--primary);
}

.kind-embed-loading,
.kind-embed-empty {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  color: var(--muted-color);
  font-style: italic;
}

.kind-embed-error {
  padding: 0.5rem 0.75rem;
  border: 1px solid #fecaca;
  border-radius: 4px;
  background: #fee2e2;
  color: #991b1b;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.spinning {
  animation: spin 1s linear infinite;
}

@media (prefers-color-scheme: dark) {
  .kind-embed-error {
    background: #450a0a;
    border-color: #7f1d1d;
    color: #fecaca;
  }
}
</style>
