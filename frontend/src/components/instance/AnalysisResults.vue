<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue'
import { executeAnalysis } from '../../api/client.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'
import AnalysisSection from './AnalysisSection.vue'

// Runs an analysis when it is shown and displays the result (the analysis page and page embeds).
// It never blocks its parent: the run is awaited here only, and the placeholder spins meanwhile.
const props = defineProps({
  name: String,
  compact: { type: Boolean, default: false },
})

const emit = defineEmits(['state'])

const result = ref(null)
const executing = ref(false)
const rootEl = ref(null)

async function run() {
  executing.value = true
  try {
    result.value = await executeAnalysis(props.name)
  } catch (e) {
    result.value = { success: false, error: e.message, sections: [] }
  } finally {
    executing.value = false
  }
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

watch([result, executing], () => emit('state', { result: result.value, executing: executing.value }), { immediate: true })

watch(result, async () => {
  await nextTick()
  if (rootEl.value) highlightCodeBlocks(rootEl.value)
})

onMounted(run)
defineExpose({ run })
</script>

<template>
<article ref="rootEl" class="analysis-execution" :class="{ compact }">
  <header v-if="!compact">
    <h3><i class="iconoir-play"></i> Results</h3>
    <div class="analysis-execute-controls">
      <button class="secondary outline" @click="run" :disabled="executing">
        <i class="iconoir-refresh" :class="{ spinning: executing }"></i>
        {{ executing ? 'Running...' : 'Re-run' }}
      </button>
    </div>
  </header>

  <div v-if="result" class="analysis-result-container" :class="result.success ? 'success' : 'failed'">
    <div v-if="!compact" class="analysis-result-header">
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
</template>

<style scoped>
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

.compact .analysis-results-placeholder {
  font-size: 0.85em;
}
</style>
