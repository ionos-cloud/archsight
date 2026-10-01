<script setup>
import { ref, computed, watch } from 'vue'
import { getPage } from '../../api/client.js'
import { searchParams } from '../../composables/useSearchScope.js'
import WikiPage from './WikiPage.vue'

const props = defineProps({
  name: String,
})

const page = ref(null)
const error = ref(null)
const hasProperties = computed(() => {
  const p = page.value
  return !!(p && (p.status || p.author || p.owner || p.tags.length || p.confluence))
})

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
}

watch(() => props.name, load, { immediate: true })

function statusClass(status) {
  return `status-${String(status).toLowerCase().replace(/[^a-z0-9]+/g, '-')}`
}

function tagQuery(tag) {
  return { name: 'search', query: searchParams(`Page: page/tags == "${tag}"`, 'pages') }
}
</script>

<template>
  <WikiPage
    v-if="page"
    :title="page.title"
    :html="page.html"
    :breadcrumb="page.breadcrumb"
    :toc="page.toc"
    :backlinks="page.backlinks"
    :edit-name="page.name"
  >
    <template v-if="$slots.actions" #actions><slot name="actions"></slot></template>
    <template #properties>
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
    </template>
  </WikiPage>
  <article v-else-if="error">
    <p>{{ error }}</p>
  </article>
  <article v-else><p>Loading...</p></article>
</template>
