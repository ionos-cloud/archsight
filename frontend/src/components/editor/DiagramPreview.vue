<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { renderDiagram } from '../../api/client.js'
import { useDiagramPreviewLayout } from '../../composables/useDiagramPreviewLayout.js'

// Live preview of Archsight diagram (.asd) source: renders on the server 300 ms after the
// source stops changing, keeps the last good diagram visible while typing or when the source
// is (temporarily) broken.
const props = defineProps({
  source: String,
})

const DEBOUNCE_MS = 300

const { layout, setLayout } = useDiagramPreviewLayout()
const hidden = computed(() => layout.value === 'hidden')

const OPTIONS = [
  { value: 'bottom', icon: 'iconoir-table-rows', label: 'Below the editor' },
  { value: 'right', icon: 'iconoir-view-columns-2', label: 'Right of the editor' },
  { value: 'full', icon: 'iconoir-expand', label: 'Preview only' },
  { value: 'hidden', icon: 'iconoir-eye-closed', label: 'Hide preview' },
]

const html = ref('')
const error = ref(null)
const rendering = ref(false)

let timer = null
let controller = null

function cancel() {
  clearTimeout(timer)
  timer = null
  controller?.abort()
  controller = null
}

async function render(source) {
  controller = new AbortController()
  const mine = controller
  rendering.value = true
  try {
    const result = await renderDiagram(source, { signal: mine.signal })
    if (mine !== controller) return
    if (result.html) html.value = result.html
    error.value = result.error
  } catch (e) {
    if (e.name === 'AbortError' || mine !== controller) return
    error.value = e.message
  } finally {
    if (mine === controller) rendering.value = false
  }
}

// nothing is rendered while the preview is hidden, showing it again renders the current source
watch([() => props.source, hidden], ([source, isHidden], [, wasHidden]) => {
  cancel()
  if (isHidden) {
    rendering.value = false
    return
  }
  if (!source || !source.trim()) {
    html.value = ''
    error.value = null
    rendering.value = false
    return
  }
  rendering.value = true
  timer = setTimeout(() => render(source), wasHidden ? 0 : DEBOUNCE_MS)
}, { immediate: true })

onBeforeUnmount(cancel)

// Resource links would leave the editor and lose unsaved changes
function blockLinks(event) {
  if (event.target.closest('a')) event.preventDefault()
}
</script>

<template>
  <div :class="['diagram-preview', `layout-${layout}`]">
    <div class="preview-head">
      <span><i class="iconoir-eye"></i> Preview<template v-if="hidden"> hidden</template></span>
      <span class="preview-tools">
        <span v-if="rendering && !hidden" class="preview-state">Rendering…</span>
        <span class="preview-layout" role="group" aria-label="Preview layout">
          <button
            v-for="option in OPTIONS.filter((o) => !hidden || o.value !== 'hidden')"
            :key="option.value"
            type="button"
            :class="{ active: layout === option.value }"
            :aria-pressed="layout === option.value"
            :title="option.label"
            :aria-label="option.label"
            @click="setLayout(option.value)"
          ><i :class="option.icon"></i></button>
        </span>
      </span>
    </div>
    <template v-if="!hidden">
    <div v-if="error" class="preview-error" role="alert">
      <i class="iconoir-warning-triangle"></i> {{ error }}
    </div>
    <div
      v-if="html"
      :class="['preview-body', { stale: !!error }]"
      title="Links are disabled in the preview"
      @click="blockLinks"
      v-html="html"
    ></div>
    <p v-else-if="!error && !rendering" class="preview-empty">Nothing to preview yet.</p>
    </template>
  </div>
</template>

<style scoped>
.diagram-preview {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  min-height: 0;
}

.preview-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  color: var(--pico-muted-color);
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.preview-tools {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
}

.preview-state {
  text-transform: none;
  letter-spacing: 0;
}

.preview-layout {
  display: inline-flex;
  gap: 0.15rem;
}

.preview-layout button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.4rem;
  height: 1.4rem;
  margin: 0;
  padding: 0;
  font-size: 0.8rem;
  color: var(--pico-muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--pico-border-radius);
  cursor: pointer;
}

.preview-layout button:hover,
.preview-layout button:focus-visible {
  color: var(--pico-primary);
  border-color: var(--pico-muted-border-color);
}

.preview-layout button.active {
  color: var(--pico-primary);
  border-color: var(--pico-primary);
}

.preview-error {
  padding: 0.35rem 0.6rem;
  border-left: 4px solid var(--pico-del-color);
  background: var(--pico-mark-background-color);
  font-size: 0.75rem;
  overflow-wrap: anywhere;
}

.preview-body {
  min-height: 0;
  overflow: auto;
}

/* the last good render while the source is broken */
.preview-body.stale {
  opacity: 0.45;
}

.preview-body :deep(.asd-diagram) {
  margin: 0;
}

.preview-empty {
  margin: 0;
  color: var(--pico-muted-color);
  font-size: 0.8rem;
}
</style>
