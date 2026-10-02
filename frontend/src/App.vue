<script setup>
import { ref, provide, computed } from 'vue'
import { useRoute } from 'vue-router'
import { getKinds, getPages } from './api/client.js'
import { useSidebarTabFollowsRoute } from './composables/useSidebarTab.js'
import NavigationBar from './components/layout/NavigationBar.vue'
import SidebarPanel from './components/layout/SidebarPanel.vue'

const route = useRoute()
const fullscreen = computed(() => route.meta.fullscreen)

const kinds = ref(null)
const kindsError = ref(null)

async function loadKinds() {
  try {
    kinds.value = await getKinds()
  } catch (e) {
    kindsError.value = e.message
  }
}
loadKinds()

const pages = ref(null)
const pageFilters = ref([])
const pageHome = ref(null) // { name, title } of the page shown at /, if there is one

async function loadPages() {
  try {
    const data = await getPages()
    pages.value = data.pages
    pageFilters.value = data.filters || []
    pageHome.value = data.home || null
  } catch {
    pages.value = []
  }
}
loadPages()

useSidebarTabFollowsRoute(route)

// name -> title of every page in the tree (menus included), for views that list pages by name
const pageTitles = computed(() => {
  const titles = {}
  const walk = (nodes) => (nodes || []).forEach((node) => {
    if (node.type === 'page') titles[node.name] = node.title
    else walk(node.children)
  })
  walk(pages.value)
  // the home page needs no menu, so it may not be in the tree
  if (pageHome.value) titles[pageHome.value.name] ??= pageHome.value.title
  return titles
})

provide('kinds', kinds)
provide('pages', pages)
provide('pageHome', pageHome)
provide('pageTitles', pageTitles)
provide('reloadKinds', loadKinds)
provide('reloadPages', loadPages)
</script>

<template>
  <template v-if="fullscreen">
    <router-view />
  </template>
  <template v-else>
    <NavigationBar />
    <main class="container-fluid">
      <SidebarPanel :kinds="kinds" :pages="pages" :page-filters="pageFilters" />
      <div class="content">
        <router-view />
      </div>
    </main>
  </template>
</template>
