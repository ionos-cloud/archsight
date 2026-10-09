<script setup>
import { keyHint } from '../../composables/useKeyHint.js'
import { computed } from 'vue'
import ResourceLinks from '../common/ResourceLinks.vue'

const props = defineProps({ annotations: Object })

// the `link/<name>` annotations as { name: url }
const links = computed(() => Object.fromEntries(
  Object.entries(props.annotations)
    .filter(([key]) => key.startsWith('link/'))
    .map(([key, url]) => [key.slice('link/'.length), url]),
))
</script>

<template>
  <tr v-if="Object.keys(links).length">
    <th scope="row" :title="keyHint('link/<name>')">Links</th>
    <td><ResourceLinks :links="links" /></td>
  </tr>
</template>
