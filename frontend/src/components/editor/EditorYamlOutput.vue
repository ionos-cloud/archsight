<script setup>
import { ref, onMounted, watch, nextTick } from 'vue'
import { saveYaml } from '../../api/client.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'

const props = defineProps({
  yaml: String,
  kind: String,
  name: String,
  contentHash: String,
  pathRef: String,
  inlineEditEnabled: Boolean,
})

const emit = defineEmits(['editAgain'])

const codeEl = ref(null)
const copyState = ref('idle')
const saveState = ref('idle')
const conflictError = ref(null)

onMounted(() => { if (codeEl.value) highlightCodeBlocks(codeEl.value) })
watch(() => props.yaml, async () => {
  await nextTick()
  if (codeEl.value) highlightCodeBlocks(codeEl.value)
})

async function copyToClipboard() {
  try {
    await navigator.clipboard.writeText(props.yaml)
    copyState.value = 'copied'
    setTimeout(() => { copyState.value = 'idle' }, 2000)
  } catch {
    // Fallback
    const textarea = document.createElement('textarea')
    textarea.value = props.yaml
    textarea.style.position = 'fixed'
    textarea.style.opacity = '0'
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand('copy')
    document.body.removeChild(textarea)
    copyState.value = 'copied'
    setTimeout(() => { copyState.value = 'idle' }, 2000)
  }
}

async function saveToFile() {
  saveState.value = 'saving'
  conflictError.value = null

  try {
    const result = await saveYaml(props.kind, props.name, props.yaml, props.contentHash)
    if (result.success) {
      saveState.value = 'saved'
      setTimeout(() => { saveState.value = 'idle' }, 2000)
    } else if (result.conflict) {
      conflictError.value = result.error
      saveState.value = 'idle'
    } else {
      alert('Save failed: ' + result.error)
      saveState.value = 'idle'
    }
  } catch (err) {
    alert('Save failed: ' + err.message)
    saveState.value = 'idle'
  }
}
</script>

<template>
  <div class="yaml-output-container">
    <div v-if="conflictError" class="conflict-error">
      <i class="iconoir-warning-triangle"></i>
      <span>{{ conflictError }}</span>
    </div>

    <p class="yaml-success">
      <i class="iconoir-check-circle"></i> Generated YAML
    </p>

    <div ref="codeEl">
      <pre id="yaml-content"><code class="language-yaml">{{ yaml }}</code></pre>
    </div>

    <footer>
      <p v-if="pathRef" class="yaml-file-info">
        <i class="iconoir-folder"></i>
        <span>Source: {{ pathRef }}</span>
      </p>
      <p v-else class="yaml-instructions">
        <i class="iconoir-info-circle"></i>
        <span>
          Copy this YAML and save it to a <code>.yaml</code> file in your resources directory,
          <br/>then reload the application.
        </span>
      </p>

      <div class="yaml-actions">
        <button
          v-if="pathRef && inlineEditEnabled"
          type="button"
          @click="saveToFile"
          :disabled="saveState === 'saving'"
          :class="{ saved: saveState === 'saved' }"
        >
          <i :class="saveState === 'saving' ? 'iconoir-refresh' : saveState === 'saved' ? 'iconoir-check' : 'iconoir-check-circle'"></i>
          {{ saveState === 'saving' ? 'Saving...' : saveState === 'saved' ? 'Saved!' : 'Save to File' }}
        </button>

        <button
          type="button"
          @click="copyToClipboard"
          :class="{ copied: copyState === 'copied' }"
        >
          <i :class="copyState === 'copied' ? 'iconoir-check' : 'iconoir-copy'"></i>
          {{ copyState === 'copied' ? 'Copied!' : 'Copy to Clipboard' }}
        </button>

        <button class="secondary" type="button" @click="$emit('editAgain')">
          <i class="iconoir-edit-pencil"></i> Edit Again
        </button>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.yaml-output-container {
  width: 100%;
}

.yaml-success {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0 0 1rem 0;
  color: var(--ins-color);
  font-weight: 500;
}

#yaml-content {
  margin: 0 calc(var(--block-spacing-horizontal) * -1);
  padding: var(--block-spacing-horizontal);
  background-color: var(--code-background-color);
  border-radius: 0;
  overflow-x: auto;
}

#yaml-content code {
  font-size: 0.9em;
  white-space: pre;
  line-height: 1.5;
  padding: 0;
}

footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
}

.yaml-file-info,
.yaml-instructions {
  display: flex;
  gap: 0.5rem;
  margin: 0;
  font-size: 0.9em;
  color: var(--muted-color);
  flex: 1;
  min-width: 0;
  line-height: 1.5;
}

.yaml-file-info {
  align-items: center;
}

.yaml-instructions {
  align-items: flex-start;
}

.yaml-file-info > span,
.yaml-instructions > span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.yaml-file-info > i,
.yaml-instructions > i {
  flex-shrink: 0;
}

.yaml-actions {
  display: flex;
  gap: 0.5rem;
  flex-shrink: 0;
}

.yaml-actions button,
.yaml-actions [role="button"] {
  width: auto;
  margin: 0;
}

.conflict-error {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 1rem;
  margin-bottom: 1rem;
  background-color: var(--pico-mark-background-color);
  color: var(--pico-del-color);
  border-radius: var(--pico-border-radius);
}

.conflict-error i {
  flex-shrink: 0;
}

@media (max-width: 768px) {
  footer {
    flex-direction: column;
    align-items: stretch;
  }
  .yaml-actions {
    flex-direction: column;
  }
  .yaml-actions button,
  .yaml-actions [role="button"] {
    width: 100%;
  }
}
</style>
