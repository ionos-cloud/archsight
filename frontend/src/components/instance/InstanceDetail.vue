<script setup>
import { ref, onMounted, onUnmounted, nextTick, computed, watch } from 'vue'
import { getInstanceDot } from '../../api/client.js'
import { renderDot } from '../../composables/useGraphviz.js'
import { initSvgPanZoom } from '../../composables/usePanZoom.js'
import { timeAgo, displayName } from '../../composables/useFormatting.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import { renderDrawioIn } from '../../composables/useDrawio.js'
import { useEmbeds } from '../../composables/useEmbeds.js'
import EmbeddedKind from '../page/EmbeddedKind.vue'
import RelationsGrid from './RelationsGrid.vue'
import ModuleGraph from './ModuleGraph.vue'
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
let graphLoaded = false
let panZoom = null
const descEl = ref(null)
useInternalLinks(descEl)
const { embeds, scanEmbeds } = useEmbeds()
// `resource` and /kinds/... links inside the diagram navigate in-app like description links
const diagramEl = ref(null)
useInternalLinks(diagramEl)
const annotations = computed(() => props.data.metadata?.annotations || {})
const hasOutgoingRelations = computed(() => Object.keys(props.data.relations || {}).length > 0)
const hasRelations = computed(() => {
  const refs = props.data.references || {}
  return hasOutgoingRelations.value || Object.keys(refs).length > 0
})

const generatedScript = computed(() => annotations.value['generated/script'])
const generatedAt = computed(() => annotations.value['generated/at'])
const description = computed(() => annotations.value['architecture/description'])
// The architecture/diagram annotation, rendered to SVG by the server. When present it is
// shown first, with a pager to swap to the generated dependency graph.
const diagramHtml = computed(() => props.data.diagram || '')
const view = ref(props.data.diagram ? 'diagram' : 'graph')

const LANG_LABELS = [
  ['go', 'Go'], ['python', 'Python'], ['java', 'Java'],
  ['typescript', 'TypeScript'], ['javascript', 'JavaScript'],
  ['rust', 'Rust'], ['ruby', 'Ruby'], ['crystal', 'Crystal'],
  ['cpp', 'C++'], ['csharp', 'C#'], ['zig', 'Zig'], ['elixir', 'Elixir'],
]
const moduleGraphs = computed(() => {
  const results = LANG_LABELS
    .filter(([lang]) => annotations.value[`architecture/${lang}/modules`])
    .map(([lang, label]) => ({ label: `${label} Module Structure`, dot: annotations.value[`architecture/${lang}/modules`] }))
  if (!results.length && annotations.value['architecture/modules'])
    results.push({ label: 'Module Structure', dot: annotations.value['architecture/modules'] })
  return results
})

// Filter out system annotations for the custom annotations table
const SKIP_PREFIXES = [
  'scc/language/', 'repository/artifacts/', 'link/', 'team/', 'jira/', 'generated/', 'license/',
]
const SKIP_KEYS = new Set([
  'scc/languages', 'architecture/description', 'architecture/diagram', 'architecture/modules',
  'workflow/platforms', 'workflow/types',
  'agentic/tools', 'repository/artifacts', 'repository/git', 'repository/visibility',
])
const SKIP_PATTERNS = [
  /^scc\/estimated(Cost|ScheduleMonths|People)$/,
  /^activity\/(commits|contributors(\/.*)?|status|busFactor|createdAt)$/,
  /^scc\/language\/.+\/loc$/,
  /^repository\/$/,
  /^architecture\/.+\/modules$/,
]

const customAnnotations = computed(() => {
  return Object.entries(annotations.value).filter(([k]) => {
    if (SKIP_KEYS.has(k)) return false
    if (SKIP_PREFIXES.some(p => k.startsWith(p))) return false
    if (SKIP_PATTERNS.some(p => p.test(k))) return false
    return true
  })
})

// The graph is only fetched and laid out once it is visible: svg-pan-zoom measures the
// container, which is 0x0 while the diagram view is showing.
async function loadGraph() {
  if (graphLoaded || !hasOutgoingRelations.value) return
  graphLoaded = true
  const dot = await getInstanceDot(props.kind, props.data.name)
  svgHtml.value = dot ? await renderDot(dot) : ''
  await nextTick()
  initPanZoomOnGraph()
}

async function showView(name) {
  view.value = name
  if (name === 'graph') await loadGraph()
}

onMounted(async () => {
  if (view.value === 'graph') await loadGraph()
  await nextTick()
  if (descEl.value) {
    renderMermaidIn(descEl.value)
    renderDrawioIn(descEl.value)
    scanEmbeds(descEl.value)
  }
})

watch(description, async () => {
  await nextTick()
  if (descEl.value) {
    renderMermaidIn(descEl.value)
    renderDrawioIn(descEl.value)
    scanEmbeds(descEl.value)
  }
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
          <span class="instance-name">{{ displayName(data.name, kind) }}</span>
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

    <div v-if="diagramHtml && hasOutgoingRelations" class="view-pager" role="group" aria-label="Diagram view">
      <button type="button" class="outline" :class="{ secondary: view !== 'diagram' }"
              :aria-pressed="view === 'diagram'" @click="showView('diagram')">
        <i class="iconoir-developer"></i> Diagram
      </button>
      <button type="button" class="outline" :class="{ secondary: view !== 'graph' }"
              :aria-pressed="view === 'graph'" @click="showView('graph')">
        <i class="iconoir-graph-up"></i> Dependencies
      </button>
    </div>
    <div v-if="diagramHtml" v-show="view === 'diagram'" ref="diagramEl" class="asd-diagram-wrap" v-html="diagramHtml"></div>

    <div v-if="hasOutgoingRelations && svgHtml" v-show="view === 'graph'" class="graph-container">
      <div id="graphviz" ref="graphEl" class="canvas" v-html="svgHtml"></div>
    </div>
    <p v-else-if="hasRelations && !hasOutgoingRelations && !diagramHtml" class="graph-too-large">
      <i class="iconoir-graph-up"></i> No outgoing dependencies — graph omitted
    </p>

    <div ref="descEl" v-if="description" v-html="description" :class="['prose', { footer: hasRelations }]"></div>
    <Teleport v-for="embed in embeds" :key="embed.key" :to="embed.el">
      <EmbeddedKind :kind="embed.kind" :name="embed.name" :spec="embed.spec" />
    </Teleport>
  </article>

  <ModuleGraph v-for="g in moduleGraphs" :key="g.label" :dot="g.dot" :label="g.label" />

  <RequirementsSection :data="data" />

  <article class="documentation">
    <header><h2>Details</h2></header>
    <table>
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
  font-size: var(--fs-xs);
  font-weight: 400;
  color: var(--pico-muted-color);
  opacity: 0.7;
  margin-top: 0.1em;
}

.view-pager[role="group"] {
  display: inline-flex;
  width: fit-content;
  margin-bottom: 0.5rem;
}

.view-pager[role="group"] button {
  flex: 0 0 auto;
  width: auto;
  margin-bottom: 0;
  padding: 0.25rem 0.75rem;
  font-size: var(--fs-xs);
}

.graph-container {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--pico-muted-border-color);
  border-radius: 4px;
  background-color: var(--pico-card-background-color);
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
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--pico-border-radius);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-header:hover {
  color: var(--pico-primary);
  border-color: var(--pico-primary);
}
</style>
