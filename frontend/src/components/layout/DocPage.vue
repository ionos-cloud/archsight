<script setup>
import { ref, watch, nextTick } from 'vue'
import { getDoc } from '../../api/client.js'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'

const props = defineProps({
  filename: String,
})

const content = ref('')
const loading = ref(true)
const articleEl = ref(null)

async function load() {
  loading.value = true
  const html = await getDoc(props.filename)
  content.value = html || '<p>Documentation not found.</p>'
  loading.value = false
  await nextTick()
  if (articleEl.value) {
    highlightCodeBlocks(articleEl.value)
    renderMermaidIn(articleEl.value)
  }
}

watch(() => props.filename, load, { immediate: true })
</script>

<template>
  <div v-if="!loading" ref="articleEl" v-html="content"></div>
  <article v-else><p>Loading...</p></article>
</template>
