<script setup>
import { ref, onMounted, onUnmounted, nextTick, computed, watch } from 'vue'
import { getInstanceDot } from '../../api/client.js'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'
import { timeAgo } from '../../composables/useFormatting.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import RelationsGrid from './RelationsGrid.vue'
import RequirementsSection from './RequirementsSection.vue'
import GitInfo from '../artifact/GitInfo.vue'
import LanguageStats from '../artifact/LanguageStats.vue'
import ProjectEstimate from '../artifact/ProjectEstimate.vue'
import RepositoriesBar from '../artifact/RepositoriesBar.vue'
import ActivityInfo from '../artifact/ActivityInfo.vue'
import TeamInfo from '../artifact/TeamInfo.vue'
import DeploymentInfo from '../artifact/DeploymentInfo.vue'
import WorkflowInfo from '../artifact/WorkflowInfo.vue'
import AgenticTools from '../artifact/AgenticTools.vue'
import LicenseInfo from '../artifact/LicenseInfo.vue'
import ExternalLinks from '../artifact/ExternalLinks.vue'
import AnnotationRow from '../artifact/AnnotationRow.vue'

const props = defineProps({
  data: Object,
  kind: String,
  kindMeta: Object,
})

const svgHtml = ref('')
const graphEl = ref(null)
let panZoom = null
const descEl = ref(null)
useInternalLinks(descEl)
const annotations = computed(() => props.data.metadata?.annotations || {})
const hasOutgoingRelations = computed(() => Object.keys(props.data.relations || {}).length > 0)
const hasRelations = computed(() => {
  const refs = props.data.references || {}
  return hasOutgoingRelations.value || Object.keys(refs).length > 0
})

const generatedScript = computed(() => annotations.value['generated/script'])
const generatedAt = computed(() => annotations.value['generated/at'])
const description = computed(() => annotations.value['architecture/description'])

// Filter out system annotations for the custom annotations table
const SKIP_PREFIXES = [
  'scc/language/', 'repository/artifacts/', 'link/', 'team/', 'jira/', 'generated/', 'license/',
]
const SKIP_KEYS = new Set([
  'scc/languages', 'architecture/description', 'workflow/platforms', 'workflow/types',
  'agentic/tools', 'repository/artifacts', 'repository/git', 'repository/visibility',
])
const SKIP_PATTERNS = [
  /^scc\/estimated(Cost|ScheduleMonths|People)$/,
  /^activity\/(commits|contributors(\/.*)?|status|busFactor|createdAt)$/,
  /^scc\/language\/.+\/loc$/,
  /^repository\/$/,
]

const customAnnotations = computed(() => {
  return Object.entries(annotations.value).filter(([k]) => {
    if (SKIP_KEYS.has(k)) return false
    if (SKIP_PREFIXES.some(p => k.startsWith(p))) return false
    if (SKIP_PATTERNS.some(p => p.test(k))) return false
    return true
  })
})

onMounted(async () => {
  if (hasOutgoingRelations.value) {
    const dot = await getInstanceDot(props.kind, props.data.name)
    svgHtml.value = dot ? await renderDot(dot) : ''
    await nextTick()
    initPanZoomOnGraph()
  }
  await nextTick()
  if (descEl.value) renderMermaidIn(descEl.value)
})

watch(description, async () => {
  await nextTick()
  if (descEl.value) renderMermaidIn(descEl.value)
})

onUnmounted(() => { panZoom?.destroy() })

function initPanZoomOnGraph() {
  if (!graphEl.value) return
  const svg = graphEl.value.querySelector('svg')
  if (!svg) return
  panZoom = initSvgPanZoom(svg, graphEl.value)
}
</script>

<template>
  <article>
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        <div class="instance-title-text">
          <span class="instance-name">{{ data.name }}</span>
          <span class="instance-kind-subtitle">{{ kind }}</span>
        </div>
      </h2>
      <div v-if="generatedScript" class="generated-badge">
        <span class="generated-script">
          by
          <router-link :to="{ name: 'instance', params: { kind: 'Import', instance: generatedScript } }">
            {{ generatedScript }}
          </router-link>
        </span>
        <span v-if="generatedAt" class="generated-time">
          generated {{ timeAgo(generatedAt) }}
        </span>
      </div>
      <router-link
        v-else
        class="btn-header"
        :to="`/kinds/${kind}/instances/${data.name}/edit`"
        title="Edit this resource"
      >
        <i class="iconoir-edit-pencil"></i> Edit
      </router-link>
    </header>

    <div v-if="hasOutgoingRelations && svgHtml" class="graph-container">
      <div id="graphviz" ref="graphEl" class="canvas" v-html="svgHtml"></div>
    </div>
    <p v-else-if="hasRelations && !hasOutgoingRelations" class="graph-too-large">
      <i class="iconoir-graph-up"></i> No outgoing dependencies — graph omitted
    </p>

    <div ref="descEl" v-if="description" v-html="description" :class="{ footer: hasRelations }"></div>
  </article>

  <RequirementsSection :data="data" />

  <article class="documentation">
    <header><h2>Details</h2></header>
    <table>
      <thead>
        <tr>
          <th scope="col">Name</th>
          <th scope="col">Value</th>
        </tr>
      </thead>
      <tbody>
        <GitInfo :annotations="annotations" />
        <LanguageStats :annotations="annotations" :kind="kind" />
        <ProjectEstimate :annotations="annotations" />
        <RepositoriesBar :annotations="annotations" />
        <ActivityInfo :annotations="annotations" :kind="kind" />
        <TeamInfo :annotations="annotations" :instance="data" />
        <DeploymentInfo :annotations="annotations" :kind="kind" />
        <WorkflowInfo :annotations="annotations" :kind="kind" />
        <AgenticTools :annotations="annotations" :kind="kind" />
        <LicenseInfo :annotations="annotations" :kind="kind" />
        <ExternalLinks :annotations="annotations" />
        <AnnotationRow
          v-for="[key, value] in customAnnotations"
          :key="key"
          :annotation-key="key"
          :value="value"
          :kind="kind"
        />
      </tbody>
    </table>
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

.instance-badges {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
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
</style>
