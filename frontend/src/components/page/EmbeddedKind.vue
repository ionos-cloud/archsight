<script setup>
import { ref, computed, watch, inject, nextTick } from 'vue'
import { getInstance, getRequirements } from '../../api/client.js'
import { viewSpec } from '../../composables/useViewSpec.js'
import { analysisStatus } from '../../composables/useAnalysisStatus.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import { renderDrawioIn } from '../../composables/useDrawio.js'
import ViewResults from '../instance/ViewResults.vue'
import AnalysisResults from '../instance/AnalysisResults.vue'
import RequirementsTable from '../instance/RequirementsTable.vue'

// The live content of a View or Analysis inside a page (an analysis runs once, when the page opens) (`![[View/Name]]`). The page is already on screen when
// this mounts; the resource, its query or script are loaded here, and a spinner shows until they are there.
// An inline view (a ```view block) brings its own `spec` (query, fields, sort, showKind) and `name` is its title:
// nothing to load but the result. The requirements of a selection of resources (a ```requirements block, kind
// 'Requirements') bring a `spec` too (`of`, `priority`, `status`) and are loaded from the API here.
// Any other kind (`![[MotivationGoal/Name]]`) shows the resource's description; embeds inside that description stay
// links, so two descriptions cannot embed each other without end.
const props = defineProps({
  kind: String,
  name: String,
  spec: { type: Object, default: null },
})

const instance = ref(null)
const total = ref(null)
const analysis = ref(null) // { result, executing } of an embedded analysis
const error = ref(null)
const requirements = ref(null) // the entries of a 'Requirements' embed
const descriptionEl = ref(null)
useInternalLinks(descriptionEl)
const kinds = inject('kinds', ref(null))
const LIVE_KINDS = ['View', 'Analysis', 'Requirements']
const isDescription = computed(() => !props.spec && !LIVE_KINDS.includes(props.kind))

async function loadRequirements() {
  requirements.value = null
  total.value = null
  error.value = null
  try {
    const result = await getRequirements(props.spec)
    requirements.value = result.requirements
    total.value = result.total
  } catch (e) {
    error.value = e.message
  }
}

async function load() {
  if (props.kind === 'Requirements') return loadRequirements()
  if (props.spec) return
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
watch(() => [props.kind, props.name, JSON.stringify(props.spec)], load, { immediate: true })

const annotations = computed(() => instance.value?.metadata?.annotations || {})
const viewSpecOf = computed(() => props.spec || viewSpec(annotations.value))
// "Completed, 1 warning 0.02s", for the line above the embedded analysis
const status = computed(() => {
  const result = analysis.value?.result
  const s = analysisStatus(result)
  if (!s) return null
  const label = s.notes ? `${s.label}, ${s.notes}` : s.label
  return { failed: s.failed, label: result.duration ? `${label} ${result.duration.toFixed(2)}s` : label }
})
const hasScript = computed(() => !!annotations.value['analysis/script'])
const description = computed(() => annotations.value['architecture/description'])
watch(description, async () => {
  await nextTick()
  if (!descriptionEl.value) return
  renderMermaidIn(descriptionEl.value)
  renderDrawioIn(descriptionEl.value)
})
const kindMeta = computed(() => kinds.value?.kinds?.find((k) => k.kind === props.kind))
const icon = computed(() => {
  if (isDescription.value) return kindMeta.value ? `iconoir-${kindMeta.value.icon} icon-${kindMeta.value.layer}` : 'iconoir-page'
  return ({ View: 'iconoir-table-rows', Requirements: 'iconoir-list' })[props.kind] || 'iconoir-play'
})
const title = computed(() => props.name || (props.kind === 'Requirements' ? 'Requirements' : 'View'))
// The "Realized by" column only helps when the requirements come from more than one resource
const showBy = computed(() => new Set((requirements.value || []).flatMap((r) => r.by.map((b) => `${b.kind}/${b.name}`))).size > 1)
const priorityLink = (priority) => `/search?q=${encodeURIComponent(`MotivationRequirement: requirement/priority == "${priority}"`)}`
</script>

<template>
  <div class="kind-embed-box">
    <p class="kind-embed-source">
      <i :class="icon"></i>
      <span v-if="spec" class="kind-embed-title">{{ title }}</span>
      <router-link v-else :to="{ name: 'instance', params: { kind, instance: name } }" :title="`Open ${kind.toLowerCase()} ${name}`">{{ name }}</router-link>
      <span v-if="isDescription" class="kind-embed-kind">{{ kind }}</span>
      <span v-if="total != null" class="kind-embed-count">({{ total }} {{ total === 1 ? 'item' : 'items' }})</span>
      <template v-if="analysis">
        <span v-if="status" class="kind-embed-status" :class="{ failed: status.failed }">({{ status.label }})</span>
        <span v-else-if="analysis.executing" class="kind-embed-status">(Running...)</span>
      </template>
    </p>

    <div v-if="error" class="kind-embed-error" role="alert">{{ error }}</div>
    <p v-else-if="kind === 'Requirements' && !requirements" class="kind-embed-loading" aria-busy="true">
      <i class="iconoir-refresh spinning"></i> Loading requirements...
    </p>
    <template v-else-if="kind === 'Requirements'">
      <RequirementsTable v-if="requirements.length" :items="requirements" :priority-link="priorityLink" :show-by="showBy" />
      <p v-else class="kind-embed-empty">No requirements</p>
    </template>
    <p v-else-if="!instance && !spec" class="kind-embed-loading" aria-busy="true">
      <i class="iconoir-refresh spinning"></i> Loading {{ kind.toLowerCase() }}...
    </p>
    <template v-else-if="kind === 'View'">
      <ViewResults v-if="viewSpecOf.query" :query="viewSpecOf.query" :fields="viewSpecOf.fields" :sort="viewSpecOf.sort" :show-kind="viewSpecOf.showKind" compact @loaded="total = $event.total" />
      <p v-else class="kind-embed-empty">No query defined</p>
    </template>
    <template v-else-if="kind === 'Analysis'">
      <AnalysisResults v-if="hasScript" :name="name" compact @state="analysis = $event" />
      <p v-else class="kind-embed-empty">No script defined for this analysis</p>
    </template>
    <template v-else>
      <div v-if="description" ref="descriptionEl" class="kind-embed-description prose" v-html="description"></div>
      <p v-else class="kind-embed-empty">No description</p>
    </template>
  </div>
</template>

<style scoped>
.kind-embed-source {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin: 0 0 0.25rem;
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
}

.kind-embed-source a {
  color: inherit;
  text-decoration: none;
}

.kind-embed-source a:hover {
  color: var(--pico-primary);
  text-decoration: underline;
}

.kind-embed-kind {
  opacity: 0.7;
}

/* the description of another resource: set off from the page's own text like a quote */
.kind-embed-description {
  padding-left: 0.75rem;
  border-left: 3px solid var(--line);
}

.kind-embed-description :deep(> :last-child) {
  margin-bottom: 0;
}

.kind-embed-status.failed {
  color: #ef4444;
}

.kind-embed-loading,
.kind-embed-empty {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  color: var(--pico-muted-color);
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
