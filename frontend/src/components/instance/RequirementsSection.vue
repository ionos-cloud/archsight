<script setup>
import { computed } from 'vue'
import { getInstance } from '../../api/client.js'
import { ref, watch } from 'vue'
import RequirementsTable from './RequirementsTable.vue'

const props = defineProps({
  data: Object,
})

// Extract requirements from relations
const requirementNames = computed(() => {
  const rels = props.data.relations || {}
  const items = []
  const verbMap = { realizes: 'implemented', partiallyRealizes: 'partial', plans: 'planned' }
  for (const [verb, status] of Object.entries(verbMap)) {
    const kinds = rels[verb] || {}
    const reqs = kinds.MotivationRequirement || kinds.motivationRequirements || []
    for (const name of reqs) {
      items.push({ name, status, verb })
    }
  }
  return items
})

// Fetch full requirement data to get priority/story annotations
const requirements = ref([])

watch(requirementNames, async (names) => {
  if (!names.length) { requirements.value = []; return }
  const results = await Promise.all(
    names.map(async (item) => {
      try {
        const data = await getInstance('MotivationRequirement', item.name)
        const annotations = data.metadata?.annotations || {}
        return {
          ...item,
          priority: annotations['requirement/priority'] || null,
          story: annotations['requirement/story'] || null,
        }
      } catch {
        return { ...item, priority: null, story: null }
      }
    })
  )
  requirements.value = results
}, { immediate: true })

function priorityQuery(priority) {
  const instanceName = props.data.name
  return `/search?q=${encodeURIComponent(`MotivationRequirement: <- "${instanceName}" & requirement/priority == "${priority}"`)}`
}
</script>

<template>
  <article v-if="requirementNames.length" class="requirements-section">
    <header><h2>Requirements</h2></header>
    <RequirementsTable :items="requirements" :priority-link="priorityQuery" />
  </article>
</template>
