<script setup>
import { ref, computed } from 'vue'
import { displayName } from '../../composables/useFormatting.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { viewSpec } from '../../composables/useViewSpec.js'
import ViewResults from './ViewResults.vue'

const props = defineProps({
  data: Object,
  kindMeta: Object,
})

const annotations = computed(() => props.data.metadata?.annotations || {})
const spec = computed(() => viewSpec(annotations.value))
const viewQuery = computed(() => spec.value.query)
const viewDescription = computed(() => annotations.value['architecture/description'])
const viewFields = computed(() => spec.value.fields)
const viewSortFields = computed(() => spec.value.sort)
const showKind = computed(() => spec.value.showKind)

const descEl = ref(null)
useInternalLinks(descEl)
</script>

<template>
  <article class="view-header">
    <header>
      <h2>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        <div class="instance-title-text">
          <span class="instance-name">{{ displayName(data.name, 'View') }}</span>
          <span class="instance-kind-subtitle">View</span>
        </div>
      </h2>
    </header>
    <div ref="descEl" v-if="viewDescription" class="description-box prose" v-html="viewDescription"></div>
    <div v-if="viewQuery" class="view-query-display">
      <p class="query-item">
        <span class="label">Query:</span>
        <code class="query-value">{{ viewQuery }}</code>
      </p>
    </div>
  </article>

  <ViewResults v-if="viewQuery" :query="viewQuery" :fields="viewFields" :sort="viewSortFields" :show-kind="showKind" />

  <article v-if="!viewQuery">
    <p class="view-empty-state"><em>No query defined</em></p>
  </article>
</template>

<style scoped>
.view-header {
  margin-bottom: 0.75rem;
}

.view-header h2 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.view-header h2 i {
  color: var(--pico-primary);
}

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

.view-query-display {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
  align-items: center;
  padding: 0.5rem 0;
}

.query-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  padding: 0;
}

.query-item .label {
  font-weight: 600;
  color: var(--pico-muted-color);
  text-transform: uppercase;
  font-size: var(--fs-xs);
}

.query-item code {
  padding: 0.25rem 0.5rem;
  background-color: var(--pico-code-background-color);
  border-radius: 4px;
}

.view-empty-state {
  padding: 1.5rem;
  text-align: center;
  color: var(--pico-muted-color);
}

</style>
