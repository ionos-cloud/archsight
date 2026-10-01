<script setup>
import { ref, computed, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
import '../../css/page.css'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import { renderDrawioIn } from '../../composables/useDrawio.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { useEmbeds } from '../../composables/useEmbeds.js'
import EmbeddedKind from './EmbeddedKind.vue'

// The reading layout of wiki pages and documentation: breadcrumb, title, optional properties, a contents
// rail that follows the scroll position and the body, whose code, diagrams and embeds are rendered here.
const props = defineProps({
  title: String,
  html: String,
  breadcrumb: { type: Array, default: () => [] }, // [{ title }]
  toc: { type: Array, default: () => [] }, // [{ level, id, text }]
  backlinks: { type: Array, default: () => [] }, // [{ name, title }]
  editName: { type: String, default: null }, // shows the pen link to the editor of this page
})

const bodyEl = ref(null)
const activeId = ref(null)
const minLevel = computed(() => Math.min(...(props.toc.map((e) => e.level) || [1])))
useInternalLinks(bodyEl)
const { embeds, scanEmbeds } = useEmbeds()

async function renderBody() {
  await nextTick()
  if (bodyEl.value) {
    highlightCodeBlocks(bodyEl.value)
    renderMermaidIn(bodyEl.value)
    renderDrawioIn(bodyEl.value)
  }
  // views and analyses load on their own: the page is shown before they are done
  scanEmbeds(bodyEl.value)
  updateActive()
}

// Contents rail: the last heading that has scrolled past the top edge is the current section
let frame = null
function updateActive() {
  frame = null
  const ids = props.toc.map((e) => e.id)
  let current = ids[0] || null
  for (const id of ids) {
    const el = document.getElementById(id)
    if (el && el.getBoundingClientRect().top <= 80) current = id
  }
  // short pages cannot scroll their last headings up to the top edge
  const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2
  if (atBottom && window.scrollY > 0 && ids.length) current = ids[ids.length - 1]
  activeId.value = current
}

function onScroll() {
  if (frame === null) frame = requestAnimationFrame(updateActive)
}

onMounted(() => window.addEventListener('scroll', onScroll, { passive: true, capture: true }))
onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScroll, { capture: true })
  if (frame !== null) cancelAnimationFrame(frame)
})

watch(() => props.html, renderBody, { immediate: true, flush: 'post' })

function scrollTo(id) {
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' })
  activeId.value = id
}
</script>

<template>
  <article :class="['wiki-page', { 'has-toc': toc.length }]">
    <div class="page-head">
      <slot name="actions"></slot>
      <router-link
        v-if="editName && !$slots.actions"
        class="page-edit"
        :to="`/kinds/Page/instances/${encodeURIComponent(editName)}/edit`"
        title="Edit page"
        aria-label="Edit page"
      ><i class="iconoir-edit-pencil"></i></router-link>
      <div v-if="breadcrumb.length" class="breadcrumb">
        <span v-for="(crumb, i) in breadcrumb" :key="i">{{ crumb.title }}</span>
      </div>
      <h1>{{ title }}</h1>
      <slot name="properties"></slot>
    </div>

    <aside v-if="toc.length" class="page-toc" aria-label="On this page">
      <span class="toc-title">On this page</span>
      <ul>
        <li v-for="entry in toc" :key="entry.id">
          <a
            :href="`#${entry.id}`"
            :style="{ paddingLeft: `${12 + (entry.level - minLevel) * 12}px` }"
            :aria-current="activeId === entry.id ? 'location' : undefined"
            @click.prevent="scrollTo(entry.id)"
          >{{ entry.text }}</a>
        </li>
      </ul>
    </aside>

    <div ref="bodyEl" class="page-body" v-html="html"></div>
    <Teleport v-for="embed in embeds" :key="`${embed.kind}/${embed.name}`" :to="embed.el">
      <EmbeddedKind :kind="embed.kind" :name="embed.name" />
    </Teleport>

    <div v-if="backlinks.length" class="page-foot">
      <strong>Linked from</strong>
      <ul>
        <li v-for="link in backlinks" :key="link.name">
          <router-link :to="{ name: 'page', params: { name: link.name } }">{{ link.title }}</router-link>
        </li>
      </ul>
    </div>
  </article>
</template>
