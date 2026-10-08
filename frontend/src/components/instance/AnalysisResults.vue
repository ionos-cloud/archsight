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

// the worst message in a group, shown on its title so a folded group still tells what is inside
const SEVERITY = { error: 'xmark-circle', warning: 'warning-triangle' }
function severity(group) {
  const levels = group.sections.filter((s) => s.type === 'message').map((s) => s.level)
  return ['error', 'warning'].find((l) => levels.includes(l))
}

const sectionGroups = computed(() => {
  if (!result.value?.sections?.length) return []
  return groupSections(result.value.sections)
})

const hasTitledGroups = computed(() => sectionGroups.value.some(g => g.title))
// one titled group needs no fold: its title is just the heading of the output
const collapsible = computed(() => sectionGroups.value.filter(g => g.title).length > 1)

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
  <div v-if="!compact" class="analysis-bar">
    <span class="status-indicator">
      <template v-if="result">
        <template v-if="result.success && result.has_findings">
          <i class="iconoir-warning-triangle status-findings"></i> Completed with findings
        </template>
        <template v-else-if="result.success">
          <i class="iconoir-check-circle status-success"></i> Completed without findings
        </template>
        <template v-else>
          <i class="iconoir-xmark-circle status-error"></i> Failed
        </template>
      </template>
      <template v-else>Running...</template>
    </span>
    <span class="analysis-bar-end">
      <span v-if="result?.duration" class="duration" title="Run time">{{ result.duration.toFixed(2) }}s</span>
      <button type="button" class="rerun" @click="run" :disabled="executing">
        <i class="iconoir-refresh" :class="{ spinning: executing }"></i>
        {{ executing ? 'Running...' : 'Re-run' }}
      </button>
    </span>
  </div>

  <div v-if="result" class="analysis-result-container" :class="result.success ? 'success' : 'failed'">
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
          <details v-else-if="collapsible" open>
            <summary>
              {{ group.title }}
              <i v-if="severity(group)" :class="[`iconoir-${SEVERITY[severity(group)]}`, `status-${severity(group)}`]"
                 :title="severity(group)"></i>
            </summary>
            <AnalysisSection v-for="(section, i) in group.sections" :key="`g${gi}-${i}`" :section="section" />
          </details>
          <template v-else>
            <h3 class="analysis-group-title">{{ group.title }}</h3>
            <AnalysisSection v-for="(section, i) in group.sections" :key="`g${gi}-${i}`" :section="section" />
          </template>
        </template>
      </template>
    </div>
  </div>

  <div v-else-if="executing && compact" class="analysis-results-placeholder">
    Running analysis...
  </div>
</article>
</template>

<style scoped>
/* the output is a card like the rest of the content (Pico's article); the toolbar is its top line */
.analysis-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  padding: 0 0 0.5rem;
  margin-bottom: 0.5rem;
  border-bottom: 1px solid var(--line);
  font-size: var(--fs-sm);
}

.status-indicator {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-weight: 600;
}

.status-success { color: #10b981; }
.status-findings { color: #f59e0b; }
.status-error { color: #ef4444; }

.analysis-bar-end {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  color: var(--pico-muted-color);
}

.analysis-bar .rerun {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  width: auto;
  margin: 0;
  padding: 0.2rem 0.4rem;
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
  background: transparent;
  border: none;
}

.analysis-bar .rerun:hover:not(:disabled),
.analysis-bar .rerun:focus-visible {
  color: var(--pico-contrast);
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.spinning {
  animation: spin 1s linear infinite;
}

.analysis-results-placeholder {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--pico-muted-color);
  font-style: italic;
  margin: 0;
}

.analysis-error-details {
  padding: 0.6rem 0.8rem;
  margin-bottom: 1rem;
  background-color: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 4px;
  color: #ef4444;
}

.analysis-error-details details { margin-top: 0.5rem; }
.analysis-error-details summary { cursor: pointer; color: var(--pico-muted-color); font-size: var(--fs-sm); }
.analysis-error-details pre { margin-top: 0.5rem; font-size: var(--fs-xs); max-height: 200px; overflow: auto; }

.analysis-group-title {
  margin: 0 0 0.5rem;
  font-size: var(--fs-md);
}

/* several groups: each one folds (all open to begin with), separated by a hairline; the chevron leads the title.
   Pico greys an open summary and adds its own chevron, so both are reset here. */
.analysis-output details {
  margin: 0;
  border-bottom: 1px solid var(--line);
}

.analysis-output details[open] > summary:not([role]),
.analysis-output details > summary:not([role]) {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  padding: 0.5rem 0;
  font-weight: 600;
  color: var(--pico-contrast);
  background: transparent;
}

.analysis-output details > summary::after { display: none; }

.analysis-output details > summary::before {
  content: '\25B6';
  font-size: var(--fs-2xs);
  color: var(--pico-muted-color);
  transition: transform 0.2s ease;
}

.analysis-output details[open] > summary::before { transform: rotate(90deg); }
.analysis-output details[open] { padding-bottom: 0.25rem; }

.compact .analysis-results-placeholder {
  font-size: var(--fs-xs);
}
</style>
