<script setup>
import { ref, computed, watch, nextTick, onMounted, onBeforeUnmount } from 'vue'
import '../../css/page.css'
import { getPage } from '../../api/client.js'
import { renderMermaidIn } from '../../composables/useMermaid.js'
import { highlightCodeBlocks } from '../../composables/useHighlight.js'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { searchParams } from '../../composables/useSearchScope.js'

const props = defineProps({
  name: String,
})

const page = ref(null)
const error = ref(null)
const bodyEl = ref(null)
const activeId = ref(null)
const hasProperties = computed(() => {
  const p = page.value
  return !!(p && (p.status || p.author || p.owner || p.tags.length || p.confluence))
})
const minLevel = computed(() => Math.min(...(page.value?.toc.map((e) => e.level) || [1])))
useInternalLinks(bodyEl)

async function load() {
  error.value = null
  try {
    page.value = await getPage(props.name)
  } catch (e) {
    page.value = null
    error.value = e.message
    return
  }
  document.title = `${page.value.title} - Archsight`
  await nextTick()
  if (bodyEl.value) {
    highlightCodeBlocks(bodyEl.value)
    renderMermaidIn(bodyEl.value)
  }
  updateActive()
}

// Contents rail: the last heading that has scrolled past the top edge is the current section
let frame = null
function updateActive() {
  frame = null
  const ids = (page.value?.toc || []).map((e) => e.id)
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

watch(() => props.name, load, { immediate: true })

function statusClass(status) {
  return `status-${String(status).toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
}

function tagQuery(tag) {
  return { name: 'search', query: searchParams(`Page: page/tags == "${tag}"`, 'pages') }
}

function scrollTo(id) {
  document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' })
  activeId.value = id
}
</script>

<template>
  <article v-if="page" :class="['wiki-page', { 'has-toc': page.toc.length }]">
    <div class="page-head">
      <slot name="actions"></slot>
      <router-link
        v-if="!$slots.actions"
        class="page-edit"
        :to="`/kinds/Page/instances/${encodeURIComponent(page.name)}/edit`"
        title="Edit page"
        aria-label="Edit page"
      ><i class="iconoir-edit-pencil"></i></router-link>
      <div v-if="page.breadcrumb.length" class="breadcrumb">
        <span v-for="crumb in page.breadcrumb" :key="crumb.name">{{ crumb.title }}</span>
      </div>
      <h1>{{ page.title }}</h1>
      <dl v-if="hasProperties" class="page-properties">
        <div v-if="page.status" class="prop">
          <dt>Status</dt>
          <dd><span :class="['status-pill', statusClass(page.status)]">{{ page.status }}</span></dd>
        </div>
        <div v-if="page.author" class="prop">
          <dt>Author</dt>
          <dd>
            <a v-if="page.author.email" :href="`mailto:${page.author.email}`">{{ page.author.name }}</a>
            <template v-else>{{ page.author.name }}</template>
          </dd>
        </div>
        <div v-if="page.owner" class="prop">
          <dt>Owner</dt>
          <dd>
            <a v-if="page.owner.email" :href="`mailto:${page.owner.email}`">{{ page.owner.name }}</a>
            <template v-else>{{ page.owner.name }}</template>
          </dd>
        </div>
        <div v-if="page.tags.length" class="prop">
          <dt>Tags</dt>
          <dd>
            <template v-for="(tag, i) in page.tags" :key="tag">
              <router-link :to="tagQuery(tag)">{{ tag }}</router-link><template v-if="i < page.tags.length - 1">, </template>
            </template>
          </dd>
        </div>
        <div v-if="page.confluence" class="prop">
          <dt>Confluence</dt>
          <dd>
            <a :href="page.confluence" target="_blank" rel="noopener">
              <i class="iconoir-open-new-window"></i> Open in Confluence
            </a>
          </dd>
        </div>
      </dl>
    </div>

    <aside v-if="page.toc.length" class="page-toc" aria-label="On this page">
      <span class="toc-title">On this page</span>
      <ul>
        <li v-for="entry in page.toc" :key="entry.id">
          <a
            :href="`#${entry.id}`"
            :style="{ paddingLeft: `${12 + (entry.level - minLevel) * 12}px` }"
            :aria-current="activeId === entry.id ? 'location' : undefined"
            @click.prevent="scrollTo(entry.id)"
          >{{ entry.text }}</a>
        </li>
      </ul>
    </aside>

    <div ref="bodyEl" class="page-body" v-html="page.html"></div>

    <div v-if="page.backlinks.length" class="page-foot">
      <strong>Linked from</strong>
      <ul>
        <li v-for="link in page.backlinks" :key="link.name">
          <router-link :to="{ name: 'page', params: { name: link.name } }">{{ link.title }}</router-link>
        </li>
      </ul>
    </div>
  </article>
  <article v-else-if="error">
    <p>{{ error }}</p>
  </article>
  <article v-else><p>Loading...</p></article>
</template>
