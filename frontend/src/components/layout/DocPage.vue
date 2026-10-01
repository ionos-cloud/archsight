<script setup>
import { ref, watch } from 'vue'
import { getDoc } from '../../api/client.js'
import WikiPage from '../page/WikiPage.vue'

// A documentation page (/doc/<name>, /doc/resources/<kind>) in the layout of wiki pages: the leading h1 of the
// markdown is the title, the contents rail lists its h2-h4 headings.
const props = defineProps({
  filename: String,
})

const doc = ref(null)

function parse(html, filename) {
  const body = new DOMParser().parseFromString(html, 'text/html').body
  // the API wraps the document in an <article>, which would be a card inside the page body
  const root = body.querySelector(':scope > article') || body
  const first = root.querySelector('h1')
  const title = first?.textContent.trim() || filename.split('/').pop().replace(/[-_]/g, ' ')
  first?.remove()
  const toc = [...root.querySelectorAll('h2[id], h3[id], h4[id]')].map((h) => ({
    level: Number(h.tagName[1]),
    id: h.id,
    text: h.textContent.trim(),
  }))
  const breadcrumb = [{ title: 'Documentation' }]
  if (filename.startsWith('resources/')) breadcrumb.push({ title: 'Resource types' })
  return { title, html: root.innerHTML, toc: toc.length >= 2 ? toc : [], breadcrumb }
}

async function load() {
  const html = await getDoc(props.filename)
  doc.value = html
    ? parse(html, props.filename)
    : { title: 'Not found', html: '<p>Documentation not found.</p>', toc: [], breadcrumb: [{ title: 'Documentation' }] }
  document.title = `${doc.value.title} - Archsight`
}

watch(() => props.filename, load, { immediate: true })
</script>

<template>
  <WikiPage v-if="doc" :title="doc.title" :html="doc.html" :breadcrumb="doc.breadcrumb" :toc="doc.toc" />
  <article v-else><p>Loading...</p></article>
</template>
