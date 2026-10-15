<script setup>
import { ref, computed } from 'vue'

// Copies `![[Kind/Name]]`, the markdown that shows this resource inside a page or a description: the result of a
// view or an analysis, the description of any other resource
const props = defineProps({
  kind: String,
  name: String,
})

const copied = ref(false)
const snippet = computed(() => `![[${props.kind}/${props.name}]]`)
const what = computed(() => ({ View: 'the result of this view', Analysis: 'the result of this analysis' })[props.kind] || 'this description')

async function copy() {
  try {
    await navigator.clipboard.writeText(snippet.value)
  } catch {
    // no clipboard (plain http on another host): show the text to copy by hand
    window.prompt('Copy this into a page:', snippet.value)
    return
  }
  copied.value = true
  setTimeout(() => { copied.value = false }, 2000)
}
</script>

<template>
  <button type="button" class="btn-embed" :title="`Copy ${snippet} to show ${what} inside a page`" @click="copy">
    <i :class="copied ? 'iconoir-check' : 'iconoir-copy'"></i> {{ copied ? 'Copied' : 'Embed' }}
  </button>
</template>

<style scoped>
.btn-embed {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  width: auto;
  margin: 0;
  padding: 0.4rem 0.75rem;
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--pico-border-radius);
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-embed:hover {
  color: var(--pico-primary);
  border-color: var(--pico-primary);
}
</style>
