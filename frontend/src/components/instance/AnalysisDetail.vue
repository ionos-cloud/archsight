<script>
import { ref, computed } from 'vue'
import { displayName } from '../../composables/useFormatting.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import RelationsGrid from './RelationsGrid.vue'
import AnalysisResults from './AnalysisResults.vue'

export default {
  components: { RelationsGrid, AnalysisResults },
  props: { data: Object, kindMeta: Object },
  setup(props) {
    const annotations = computed(() => props.data.metadata?.annotations || {})
    // `analysis/description` is the analysis' own plain-text summary; `architecture/description` (markdown, html
    // from the API) is the generic one
    const summary = computed(() => annotations.value['analysis/description'])
    const description = computed(() => annotations.value['architecture/description'])
    const analysisScript = computed(() => annotations.value['analysis/script'])

    const descEl = ref(null)
    useInternalLinks(descEl)

    return {
      annotations, summary, description, analysisScript,
      descEl, displayName
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
          <span class="instance-name">{{ displayName(data.name, 'Analysis') }}</span>
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
    <p v-if="summary" class="analysis-summary">{{ summary }}</p>
    <div ref="descEl" v-if="description" class="description-box prose" v-html="description"></div>
  </article>

  <AnalysisResults v-if="analysisScript" :name="data.name" />

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
  font-size: var(--fs-xs);
  font-weight: 400;
  color: var(--pico-muted-color);
  opacity: 0.7;
  margin-top: 0.1em;
}

.instance-name {
  font-weight: 600;
  font-size: 1em;
  color: var(--pico-primary);
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

.analysis-header {
  margin-bottom: 0.75rem;
}

/* what the analysis checks, in one line under the title */
.analysis-summary {
  margin: 0.25rem 0 0;
  color: var(--pico-muted-color);
}

.analysis-header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.analysis-empty-state {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 1.5rem;
  color: var(--pico-muted-color);
}
</style>
