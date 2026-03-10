<script setup>
import { computed } from 'vue'

const props = defineProps({ annotations: Object, kind: String })

const types = computed(() => {
  const raw = props.annotations['repository/artifacts'] || 'none'
  return raw.split(',').map(t => t.trim())
})

const hasDeployment = computed(() => types.value[0] !== 'none')

const deploymentTypes = [
  { key: 'container', icon: 'iconoir-box', label: 'Container Image' },
  { key: 'chart', icon: 'iconoir-packages', label: 'Helm Chart' },
  { key: 'binary', icon: 'iconoir-terminal', label: 'Binary' },
  { key: 'debian', icon: 'iconoir-package', label: 'Debian Package' },
  { key: 'rpm', icon: 'iconoir-package', label: 'RPM Package' },
]

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}
</script>

<template>
  <tr v-if="hasDeployment">
    <th scope="row">Deployment Artifacts</th>
    <td>
      <div class="deployment-types">
        <template v-for="dt in deploymentTypes" :key="dt.key">
          <router-link
            v-if="types.includes(dt.key)"
            class="deployment-item"
            :to="filterUrl('repository/artifacts', dt.key)"
          >
            <i :class="dt.icon"></i>
            <strong>{{ dt.label }}</strong>
          </router-link>
        </template>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.deployment-types {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.5rem;
}

.deployment-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 6px;
  text-decoration: none;
  color: var(--color);
  transition: border-color 0.2s ease;
}

.deployment-item:hover {
  border-color: var(--primary);
}

.deployment-item i {
  color: var(--primary);
  font-size: 1.2em;
  flex-shrink: 0;
}
</style>
