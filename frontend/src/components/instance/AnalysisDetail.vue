<script>
import { ref, computed } from 'vue'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import RelationsGrid from './RelationsGrid.vue'
import AnalysisResults from './AnalysisResults.vue'

export default {
  components: { RelationsGrid, AnalysisResults },
  props: { data: Object, kindMeta: Object },
  setup(props) {
    const annotations = computed(() => props.data.metadata?.annotations || {})
    const description = computed(() => annotations.value['architecture/description'])
    const analysisScript = computed(() => annotations.value['analysis/script'])
    const handler = computed(() => annotations.value['analysis/handler'] || 'ruby')
    const timeout = computed(() => annotations.value['analysis/timeout'] || '30s')

    const descEl = ref(null)
    useInternalLinks(descEl)
    function copyScript() {
      if (analysisScript.value) navigator.clipboard.writeText(analysisScript.value)
    }

    return {
      annotations, description, analysisScript, handler, timeout,
      descEl, copyScript
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
    <div ref="descEl" v-if="description" class="description-box prose" v-html="description"></div>
  </article>

  <template v-if="analysisScript">
    <AnalysisResults :name="data.name" />

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

.analysis-header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
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
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
  padding: 0.25rem 0.5rem;
  background-color: var(--pico-code-background-color);
  border-radius: 4px;
}

.analysis-meta-item i {
  font-size: var(--fs-md);
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
  font-family: var(--font-mono);
  font-size: var(--fs-sm);
  line-height: 1.5;
}

.analysis-script-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
}

.analysis-script-header .copy-button {
  padding: 0.25rem 0.5rem;
  font-size: var(--fs-xs);
}

.copy-button {
  padding: 6px;
  background-color: transparent;
  color: var(--pico-primary);
  border: 1px solid var(--pico-muted-border-color);
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
  background-color: var(--pico-card-background-color);
  border-color: var(--pico-primary);
}

.analysis-details-section {
  margin-top: 1rem;
  border: 1px solid var(--pico-muted-border-color);
  border-radius: 8px;
  background-color: var(--pico-card-background-color);
}

.analysis-details-section summary {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1rem;
  cursor: pointer;
  font-weight: 600;
  color: var(--pico-muted-color);
  user-select: none;
}

.analysis-details-section summary:hover { color: var(--pico-color); }

.analysis-details-section summary::marker,
.analysis-details-section summary::-webkit-details-marker { display: none; }

.analysis-details-section summary::before {
  content: '\25B6';
  font-size: var(--fs-2xs);
  transition: transform 0.2s ease;
}

.analysis-details-section[open] summary::before { transform: rotate(90deg); }
.analysis-details-section[open] { padding-bottom: 0; }

.analysis-details-content {
  padding: 1rem;
  border-top: 1px solid var(--pico-muted-border-color);
}

.analysis-details-content .analysis-metadata { margin-bottom: 1rem; }
.analysis-details-content .analysis-script { border: none; margin: 0; }

.analysis-empty-state {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 1.5rem;
  color: var(--pico-muted-color);
}
</style>
