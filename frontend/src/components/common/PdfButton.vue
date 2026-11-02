<script setup>
import { ref } from 'vue'
import { pdfUrl } from '../../api/client.js'

// Downloads the page or resource as PDF. The server typesets it (Typst), which takes a moment, so the request is
// made here to show progress and the reason when it fails (no typst installed, a document that does not typeset).
const props = defineProps({
  kind: { type: String, default: null }, // none or 'Page' for a page
  name: String,
  compact: Boolean, // icon only
})

const busy = ref(false)
const failure = ref('')

function filename(res) {
  const match = /filename="([^"]+)"/.exec(res.headers.get('Content-Disposition') || '')
  return match ? match[1] : `${props.name}.pdf`
}

async function download() {
  busy.value = true
  failure.value = ''
  try {
    const res = await fetch(pdfUrl(props.kind, props.name))
    if (!res.ok) {
      const err = await res.json().catch(() => ({ message: res.statusText }))
      throw new Error(err.message || res.statusText)
    }
    const url = URL.createObjectURL(await res.blob())
    const link = Object.assign(document.createElement('a'), { href: url, download: filename(res) })
    document.body.appendChild(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10000)
  } catch (e) {
    failure.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <button
    type="button"
    :class="['btn-pdf', { compact, failed: failure }]"
    :disabled="busy"
    :title="busy ? 'Creating the PDF…' : failure ? `PDF failed: ${failure}` : 'Download as PDF'"
    aria-label="Download as PDF"
    @click="download"
  >
    <i :class="busy ? 'iconoir-refresh spin' : failure ? 'iconoir-warning-triangle' : 'iconoir-page'"></i>
    <template v-if="!compact"> {{ busy ? 'Creating PDF…' : 'PDF' }}</template>
  </button>
</template>

<style scoped>
.btn-pdf {
  display: inline-flex;
  align-items: center;
  justify-content: center;
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

.btn-pdf.compact {
  width: 2rem;
  height: 2rem;
  padding: 0;
}

.btn-pdf:hover:not(:disabled),
.btn-pdf:focus-visible {
  color: var(--pico-primary);
  border-color: var(--pico-primary);
}

.btn-pdf.failed {
  color: var(--pico-del-color);
}

/* the icon turns while the server typesets (Pico's own busy spinner is not used: the icon is the indicator) */
.btn-pdf:disabled {
  opacity: 1;
  cursor: progress;
}

.spin {
  animation: pdf-spin 0.9s linear infinite;
}

@keyframes pdf-spin {
  to { transform: rotate(360deg); }
}

@media (prefers-reduced-motion: reduce) {
  .spin { animation: none; }
}
</style>
