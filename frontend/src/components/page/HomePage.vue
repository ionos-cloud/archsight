<script setup>
import { computed, inject, defineAsyncComponent } from 'vue'
import PageView from './PageView.vue'

// The start page: the page called "Home" (the API says which one) replaces the generated
// architecture overview; without one the overview stays.
const GraphView = defineAsyncComponent(() => import('../instance/GraphView.vue'))

const pages = inject('pages', null)
const pageHome = inject('pageHome', null)

// null while the page list is loading, so the overview does not flash before the Home page
const loaded = computed(() => pages?.value != null)
const home = computed(() => pageHome?.value)
</script>

<template>
  <PageView v-if="home" :name="home.name" />
  <GraphView v-else-if="loaded" />
  <article v-else><p>Loading...</p></article>
</template>
