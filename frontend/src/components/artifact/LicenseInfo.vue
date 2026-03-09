<script setup>
import { computed } from 'vue'

const props = defineProps({ annotations: Object, kind: String })

const spdx = computed(() => props.annotations['license/spdx'])
const category = computed(() => props.annotations['license/category'] || 'unknown')
const depCount = computed(() => props.annotations['license/dependencies/count'])
const ecosystems = computed(() => (props.annotations['license/dependencies/ecosystems'] || '').split(',').map(e => e.trim()).filter(Boolean))
const risk = computed(() => props.annotations['license/dependencies/risk'] || 'unknown')
const copyleft = computed(() => props.annotations['license/dependencies/copyleft'] || 'unknown')
const depLicenses = computed(() => (props.annotations['license/dependencies/licenses'] || '').split(',').map(l => l.trim()).filter(Boolean))

const badgeClass = computed(() => {
  switch (category.value) {
    case 'permissive': return 'badge-success'
    case 'weak-copyleft': return 'badge-warning'
    case 'copyleft': return 'badge-danger'
    default: return 'badge-secondary'
  }
})

const riskClass = computed(() => {
  switch (risk.value) {
    case 'low': return 'badge-success'
    case 'weak-copyleft': return 'badge-warning'
    case 'copyleft': return 'badge-danger'
    default: return 'badge-secondary'
  }
})

const riskTitle = computed(() => {
  switch (risk.value) {
    case 'copyleft': return 'Copyleft dependencies (GPL, AGPL) or >50% unknown licenses'
    case 'weak-copyleft': return 'Weak-copyleft dependencies (LGPL, MPL) present'
    case 'low': return 'All dependencies have known permissive licenses'
    default: return 'No dependency license data available'
  }
})

const sortedLicenses = computed(() => {
  const known = depLicenses.value.filter(l => l !== 'unknown')
  return known.map(lic => ({
    name: lic,
    count: parseInt(props.annotations[`license/dependencies/${lic}/count`] || '0', 10)
  })).sort((a, b) => b.count - a.count)
})

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}
</script>

<template>
  <tr v-if="spdx">
    <th scope="row">License</th>
    <td>
      <div class="activity-summary">
        <div class="activity-item">
          <i class="iconoir-shield-check"></i>
          <router-link :class="['badge', badgeClass]" :to="filterUrl('license/spdx', spdx)">
            {{ spdx }}
          </router-link>
          <router-link v-if="category !== 'unknown'" class="badge badge-outline" :to="filterUrl('license/category', category)">
            {{ category }}
          </router-link>
        </div>

        <div v-if="depCount && parseInt(depCount) > 0" class="activity-item">
          <i class="iconoir-box"></i>
          <span class="activity-label">Dependencies:</span>
          <span class="activity-value">{{ depCount }}</span>
          <router-link
            v-for="eco in ecosystems"
            :key="eco"
            class="badge badge-info"
            :to="filterUrl('license/dependencies/ecosystems', eco)"
          >{{ eco }}</router-link>
          <router-link
            :class="['badge', riskClass]"
            :title="riskTitle"
            :to="filterUrl('license/dependencies/risk', risk)"
          >Risk: {{ risk }}</router-link>
          <router-link
            v-if="copyleft === 'true'"
            class="badge badge-warning"
            :to="filterUrl('license/dependencies/copyleft', 'true')"
          >Copyleft present</router-link>
        </div>

        <div v-if="sortedLicenses.length" class="activity-item">
          <i class="iconoir-list"></i>
          <span class="activity-label">Types:</span>
          <router-link
            v-for="lic in sortedLicenses.slice(0, 5)"
            :key="lic.name"
            class="badge badge-outline"
            :to="filterUrl('license/dependencies/licenses', lic.name)"
          >{{ lic.count > 0 ? `${lic.name} (${lic.count})` : lic.name }}</router-link>
          <details v-if="sortedLicenses.length > 5" class="license-details-inline">
            <summary class="badge badge-secondary">+{{ sortedLicenses.length - 5 }} more</summary>
            <div class="license-overflow">
              <router-link
                v-for="lic in sortedLicenses.slice(5)"
                :key="lic.name"
                class="badge badge-outline"
                :to="filterUrl('license/dependencies/licenses', lic.name)"
              >{{ lic.count > 0 ? `${lic.name} (${lic.count})` : lic.name }}</router-link>
            </div>
          </details>
        </div>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.activity-summary {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  padding: 4px 0;
}

.activity-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.activity-item i {
  font-size: 1.2em;
  color: var(--primary);
}

.activity-label {
  color: var(--muted-color);
  font-size: 0.9em;
}

.activity-value {
  font-weight: 600;
  color: var(--color);
}

.license-details-inline {
  display: inline;
}

.license-details-inline summary {
  cursor: pointer;
  list-style: none;
}

.license-details-inline summary::-webkit-details-marker {
  display: none;
}

.license-overflow {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 6px;
}
</style>
