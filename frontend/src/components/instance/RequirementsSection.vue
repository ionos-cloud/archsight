<script setup>
import { computed } from 'vue'
import { getInstance } from '../../api/client.js'
import { ref, watch } from 'vue'

const props = defineProps({
  data: Object,
})

// Extract business requirements from relations
const requirementNames = computed(() => {
  const rels = props.data.relations || {}
  const items = []
  const verbMap = { realizes: 'implemented', partiallyRealizes: 'partial', plans: 'planned' }
  for (const [verb, status] of Object.entries(verbMap)) {
    const kinds = rels[verb] || {}
    const reqs = kinds.BusinessRequirement || kinds.businessRequirements || []
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
        const data = await getInstance('BusinessRequirement', item.name)
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

function statusIcon(status) {
  switch (status) {
    case 'implemented': return 'iconoir-check-circle'
    case 'partial': return 'iconoir-half-moon'
    case 'planned': return 'iconoir-calendar'
    default: return 'iconoir-circle'
  }
}

function priorityQuery(priority) {
  const instanceName = props.data.name
  return `/search?q=${encodeURIComponent(`BusinessRequirement: <- "${instanceName}" & requirement/priority == "${priority}"`)}`
}
</script>

<template>
  <article v-if="requirementNames.length" class="requirements-section">
    <header><h2>Business Requirements</h2></header>
    <table class="requirements-table">
      <thead>
        <tr>
          <th></th>
          <th>Name</th>
          <th>Priority</th>
          <th>Story</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="req in requirements" :key="req.name">
          <td class="requirement-status">
            <i :class="[statusIcon(req.status), `status-${req.status}`]" class="requirement-status-icon" :title="req.status"></i>
          </td>
          <td>
            <router-link :to="{ name: 'instance', params: { kind: 'BusinessRequirement', instance: req.name } }">
              {{ req.name }}
            </router-link>
          </td>
          <td>
            <router-link v-if="req.priority" class="badge badge-info" :to="priorityQuery(req.priority)">
              {{ req.priority }}
            </router-link>
            <span v-else class="view-empty-value">-</span>
          </td>
          <td class="requirement-story">
            <div v-if="req.story" v-html="req.story"></div>
            <span v-else class="view-empty-value">-</span>
          </td>
        </tr>
      </tbody>
    </table>
  </article>
</template>

<style scoped>
.requirement-status-icon {
  font-size: 1.2em;
}

.requirement-status-icon.status-implemented {
  color: #10b981;
}

.requirement-status-icon.status-partial {
  color: #f59e0b;
}

.requirement-status-icon.status-planned {
  color: #3b82f6;
}

.requirement-status-icon.status-not-started,
.requirement-status-icon.status-unknown {
  color: #9ca3af;
}
</style>
