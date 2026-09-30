<script setup>
import { computed, inject, defineAsyncComponent } from 'vue'
import PageView from './PageView.vue'

// The start page: a page called "Home" (by name or title, any case) replaces the generated
// architecture overview; without one the overview stays.
const GraphView = defineAsyncComponent(() => import('../instance/GraphView.vue'))

const pages = inject('pages', null)

function findHome(nodes) {
  for (const node of nodes || []) {
    if (node.type === 'page' && [node.name, node.title].some((t) => String(t).toLowerCase() === 'home')) return node
    const found = node.type === 'menu' ? findHome(node.children) : null
    if (found) return found
  }
  return null
}

// null while the page tree is loading, so the overview does not flash before the Home page
const loaded = computed(() => pages?.value != null)
const home = computed(() => findHome(pages?.value))
</script>

<template>
  <PageView v-if="home" :name="home.name" />
  <GraphView v-else-if="loaded" />
  <article v-else><p>Loading...</p></article>
</template>
