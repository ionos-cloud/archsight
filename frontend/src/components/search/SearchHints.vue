<script setup>
import { computed, inject } from 'vue'
import { searchParams } from '../../composables/useSearchScope.js'

// What the page says when there is nothing to list: before the first query (intro) and after a query without hits (empty)
const props = defineProps({
  mode: { type: String, required: true }, // 'intro' | 'empty'
  query: { type: String, default: '' },
  scope: { type: String, default: 'kinds' },
})

const pages = inject('pages', null)
const hasPages = computed(() => !!pages?.value?.length)

const EXAMPLES = {
  kinds: [
    { query: 'kubernetes', note: 'names that contain a word' },
    { query: 'TechnologyArtifact: activity/status == "active"', note: 'active repositories' },
    { query: 'MotivationRequirement: requirement/priority == "must"', note: 'requirements that must be met' },
    { query: '-> ApplicationInterface', note: 'resources that use an interface' },
  ],
  pages: [
    { query: 'handbook', note: 'words in a page title, name or text' },
    { query: 'page/status == "rfc"', note: 'pages in review' },
  ],
}

const examples = computed(() => EXAMPLES[props.scope] || EXAMPLES.kinds)
const noun = computed(() => (props.scope === 'pages' ? 'pages' : 'resources'))

function to(example) {
  return { name: 'search', query: searchParams(example.query, props.scope) }
}
</script>

<template>
  <section v-if="mode === 'intro'" class="search-hints">
    <p class="hint-lead">Search {{ noun }} by name, or filter them with a query.</p>
    <ul class="hint-examples">
      <li v-for="example in examples" :key="example.query">
        <router-link :to="to(example)"><code>{{ example.query }}</code></router-link>
        <span class="hint-note">{{ example.note }}</span>
      </li>
    </ul>
    <p><router-link to="/doc/search">Query syntax</router-link></p>
  </section>

  <section v-else class="search-hints">
    <p class="hint-lead">No {{ noun }} match <code>{{ query }}</code>.</p>
    <ul class="hint-tips">
      <li>Check the spelling, or try a shorter word.</li>
      <li v-if="scope === 'kinds' && hasPages">Page texts are searched from the Pages tab.</li>
      <li v-if="scope === 'pages'">Switch to the Kinds tab to search resources.</li>
    </ul>
    <p><router-link to="/doc/search">Query syntax</router-link></p>
  </section>
</template>

<style scoped>
.search-hints {
  padding: 0.5rem 0 1rem;
  color: var(--pico-muted-color);
}

.hint-lead {
  margin-bottom: 0.5rem;
  color: var(--pico-color);
}

.hint-examples,
.hint-tips {
  margin: 0 0 0.75rem;
  padding: 0;
  list-style: none;
}

.hint-examples li,
.hint-tips li {
  margin: 0;
  list-style: none; /* Pico gives list items a square marker */
  padding: 0.2rem 0;
  font-size: var(--fs-sm);
}

.hint-examples code {
  padding: 2px 6px;
  font-size: var(--fs-xs);
}

.hint-note {
  margin-left: 0.6rem;
  font-size: var(--fs-xs);
}

.search-hints a {
  text-decoration: none;
}

.search-hints a:hover {
  text-decoration: underline;
}
</style>
