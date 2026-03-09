<script>
import { ref, computed, onMounted, watch, nextTick, h } from 'vue'
import { executeAnalysis } from '../../api/client.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'
import RelationsGrid from './RelationsGrid.vue'
import AnalysisSection from './AnalysisSection.vue'

export default {
  components: { RelationsGrid, AnalysisSection },
  props: { data: Object, kindMeta: Object },
  setup(props) {
    const annotations = computed(() => props.data.metadata?.annotations || {})
    const description = computed(() => annotations.value['architecture/description'])
    const analysisScript = computed(() => annotations.value['analysis/script'])
    const handler = computed(() => annotations.value['analysis/handler'] || 'ruby')
    const timeout = computed(() => annotations.value['analysis/timeout'] || '30s')

    const descEl = ref(null)
    useInternalLinks(descEl)
    const result = ref(null)
    const executing = ref(false)

    async function run() {
      executing.value = true
      result.value = await executeAnalysis(props.data.name)
      executing.value = false
    }

    function copyScript() {
      if (analysisScript.value) navigator.clipboard.writeText(analysisScript.value)
    }

    function groupSections(sections) {
      const groups = []
      let current = { title: null, sections: [] }
      for (const section of sections) {
        if (section.type === 'heading' && section.level === 0) {
          if (current.title || current.sections.length) groups.push(current)
          current = { title: section.text, sections: [] }
        } else {
          current.sections.push(section)
        }
      }
      if (current.title || current.sections.length) groups.push(current)
      return groups
    }

    const sectionGroups = computed(() => {
      if (!result.value?.sections?.length) return []
      return groupSections(result.value.sections)
    })

    const hasTitledGroups = computed(() => sectionGroups.value.some(g => g.title))
    const rootEl = ref(null)

    watch(result, async () => {
      await nextTick()
      if (rootEl.value) highlightCodeBlocks(rootEl.value)
    })

    onMounted(() => {
      if (analysisScript.value) run()
    })

    return {
      annotations, description, analysisScript, handler, timeout,
      descEl, rootEl, result, executing, sectionGroups, hasTitledGroups,
      run, copyScript
    }
  }
}
</script>

<template>
  <article class="analysis-header">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        <div class="instance-title-text">
          <span class="instance-name">{{ data.name }}</span>
          <span class="instance-kind-subtitle">Analysis</span>
        </div>
      </h2>
      <div class="header-actions">
        <router-link
          class="btn-header"
          :to="`/kinds/Analysis/instances/${data.name}/edit`"
          title="Edit this resource"
        >
          <i class="iconoir-edit-pencil"></i> Edit
        </router-link>
      </div>
    </header>
    <div ref="descEl" v-if="description" class="analysis-description" v-html="description"></div>
  </article>

  <template v-if="analysisScript">
    <article ref="rootEl" class="analysis-execution">
      <header>
        <h3><i class="iconoir-play"></i> Results</h3>
        <div class="analysis-execute-controls">
          <button class="secondary outline" @click="run" :disabled="executing">
            <i class="iconoir-refresh" :class="{ spinning: executing }"></i>
            {{ executing ? 'Running...' : 'Re-run' }}
          </button>
        </div>
      </header>

      <div v-if="result" class="analysis-result-container" :class="result.success ? 'success' : 'failed'">
        <div class="analysis-result-header">
          <span class="status-indicator">
            <template v-if="result.success">
              <template v-if="result.has_findings">
                <i class="iconoir-warning-triangle status-findings"></i> Completed with findings
              </template>
              <template v-else>
                <i class="iconoir-check-circle status-success"></i> Completed successfully
              </template>
            </template>
            <template v-else>
              <i class="iconoir-xmark-circle status-error"></i> Failed
            </template>
          </span>
          <span v-if="result.duration" class="duration">
            <i class="iconoir-timer"></i> {{ result.duration.toFixed(2) }}s
          </span>
        </div>

        <div v-if="!result.success" class="analysis-error-details">
          <strong>Error:</strong> {{ result.error }}
          <details v-if="result.error_backtrace?.length">
            <summary>Show backtrace</summary>
            <pre class="code">{{ result.error_backtrace.join('\n') }}</pre>
          </details>
        </div>

        <div v-if="result.sections?.length" class="analysis-output">
          <template v-if="!hasTitledGroups">
            <AnalysisSection v-for="(section, i) in sectionGroups[0]?.sections" :key="i" :section="section" />
          </template>
          <template v-else>
            <template v-for="(group, gi) in sectionGroups" :key="gi">
              <template v-if="!group.title">
                <AnalysisSection v-for="(section, i) in group.sections" :key="`u${i}`" :section="section" />
              </template>
              <template v-else>
                <hr v-if="gi > 0 && sectionGroups[gi - 1]?.title" />
                <details :open="gi === 0 || (gi === 1 && !sectionGroups[0].title)">
                  <summary>{{ group.title }}</summary>
                  <AnalysisSection v-for="(section, i) in group.sections" :key="`g${gi}-${i}`" :section="section" />
                </details>
              </template>
            </template>
          </template>
        </div>
      </div>

      <div v-else-if="executing" class="analysis-results-placeholder">
        Running analysis...
      </div>
    </article>

    <details class="analysis-details-section">
      <summary>
        <i class="iconoir-code-brackets-square"></i>
        Script Details
      </summary>
      <div class="analysis-details-content">
        <div class="analysis-metadata">
          <span class="analysis-meta-item">
            <i class="iconoir-code"></i> {{ handler }}
          </span>
          <span class="analysis-meta-item">
            <i class="iconoir-timer"></i> {{ timeout }}
          </span>
        </div>
        <div class="analysis-script">
          <div class="analysis-script-header">
            <strong>Script</strong>
            <button class="copy-button" @click="copyScript" title="Copy script to clipboard">
              <i class="iconoir-copy"></i>
            </button>
          </div>
          <pre class="code"><code class="language-ruby">{{ analysisScript }}</code></pre>
        </div>
      </div>
    </details>
  </template>

  <article v-else>
    <p class="analysis-empty-state">
      <i class="iconoir-warning-triangle"></i>
      No script defined for this analysis.
    </p>
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

.instance-name {
  font-weight: 600;
  font-size: 1em;
  color: var(--primary);
  text-decoration: none;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
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

.analysis-header {
  margin-bottom: 0.75rem;
}

.analysis-header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.analysis-description {
  margin-top: 0.75rem;
  padding: 0.75rem;
  background-color: var(--card-background-color);
  border-radius: 8px;
  border: 1px solid var(--muted-border-color);
}

.analysis-metadata {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: center;
  padding: 0.75rem 0;
  margin-top: 0.5rem;
}

.analysis-meta-item {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.9em;
  color: var(--muted-color);
  padding: 0.25rem 0.5rem;
  background-color: var(--code-background-color);
  border-radius: 4px;
}

.analysis-meta-item i {
  font-size: 1.1em;
}

.analysis-script pre.code {
  margin: 0;
  white-space: pre;
  overflow-x: auto;
  min-height: 300px;
  max-height: 600px;
  overflow-y: auto;
}

.analysis-script pre.code code {
  white-space: pre;
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  font-size: 0.9em;
  line-height: 1.5;
}

.analysis-execution header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.analysis-execution header h3 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
}

.analysis-execute-controls {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.analysis-execute-controls button {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.4rem 0.75rem;
  font-size: 0.85em;
  margin: 0;
}

.analysis-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 2rem;
  color: var(--muted-color);
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.spinning {
  animation: spin 1s linear infinite;
}

.analysis-results {
  min-height: 100px;
  padding: 1rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 8px;
}

.analysis-results-placeholder {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--muted-color);
  font-style: italic;
  margin: 0;
}

.analysis-empty-state {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 1.5rem;
  color: var(--muted-color);
}

.analysis-result-container {
  padding: 0;
}

.analysis-result-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1rem;
  margin: -1rem -1rem 1rem -1rem;
  background-color: var(--code-background-color);
  border-radius: 8px 8px 0 0;
  border-bottom: 1px solid var(--muted-border-color);
}

.analysis-result-header .status-indicator {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 600;
}

.analysis-result-header .status-success { color: #10b981; }
.analysis-result-header .status-findings { color: #f59e0b; }
.analysis-result-header .status-error { color: #ef4444; }

.analysis-result-header .duration {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  font-size: 0.9em;
  color: var(--muted-color);
}

.analysis-error-details {
  padding: 0.75rem 1rem;
  margin-bottom: 1rem;
  background-color: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 4px;
  color: #ef4444;
}

.analysis-error-details details { margin-top: 0.5rem; }
.analysis-error-details summary { cursor: pointer; color: var(--muted-color); font-size: 0.9em; }
.analysis-error-details pre { margin-top: 0.5rem; font-size: 0.85em; max-height: 200px; overflow: auto; }

.analysis-output { margin-top: 0.5rem; }

.analysis-script-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.analysis-script-header .copy-button {
  padding: 0.25rem 0.5rem;
  font-size: 0.85em;
}

.copy-button {
  padding: 6px;
  background-color: transparent;
  color: var(--primary);
  border: 1px solid var(--muted-border-color);
  border-radius: 4px;
  cursor: pointer;
  transition: all 0.2s ease;
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 32px;
  height: 32px;
}

.copy-button:hover {
  background-color: var(--card-background-color);
  border-color: var(--primary);
}

.analysis-details-section {
  margin-top: 1rem;
  border: 1px solid var(--muted-border-color);
  border-radius: 8px;
  background-color: var(--card-background-color);
}

.analysis-details-section summary {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  cursor: pointer;
  font-weight: 600;
  color: var(--muted-color);
  user-select: none;
}

.analysis-details-section summary:hover { color: var(--color); }

.analysis-details-section summary::marker,
.analysis-details-section summary::-webkit-details-marker { display: none; }

.analysis-details-section summary::before {
  content: '\25B6';
  font-size: 0.7em;
  transition: transform 0.2s ease;
}

.analysis-details-section[open] summary::before { transform: rotate(90deg); }
.analysis-details-section[open] { padding-bottom: 0; }

.analysis-details-content {
  padding: 1rem;
  border-top: 1px solid var(--muted-border-color);
}

.analysis-details-content .analysis-metadata { margin-bottom: 1rem; }
.analysis-details-content .analysis-script { border: none; margin: 0; }
</style>
