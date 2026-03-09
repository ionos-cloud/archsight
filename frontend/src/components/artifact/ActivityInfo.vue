<script setup>
import { computed } from 'vue'
import SparklineChart from '../SparklineChart.vue'

const props = defineProps({ annotations: Object, kind: String })

const commits = computed(() => props.annotations['activity/commits'])
const contributors = computed(() => props.annotations['activity/contributors'])
const contributors6m = computed(() => props.annotations['activity/contributors/6m'])
const contributorsTotal = computed(() => props.annotations['activity/contributors/total'])
const status = computed(() => props.annotations['activity/status'])
const busFactor = computed(() => props.annotations['activity/busFactor'])
const createdAt = computed(() => props.annotations['activity/createdAt'])
const hasActivity = computed(() => commits.value || contributors.value || status.value || busFactor.value || createdAt.value)

const commitsTotal = computed(() => {
  if (!commits.value) return 0
  return commits.value.split(',').map(Number).reduce((a, b) => a + b, 0)
})

const createdDate = computed(() => {
  if (!createdAt.value) return null
  const d = new Date(createdAt.value)
  return d.toLocaleDateString('en', { month: 'short', year: 'numeric' })
})

const busFactorTitle = computed(() => {
  const bf = busFactor.value
  let title = ''
  switch (bf) {
    case 'high': title = 'High risk: One contributor accounts for >75% of commits in the last 6 months'; break
    case 'medium': title = 'Medium risk: One contributor accounts for 50-75% of commits in the last 6 months'; break
    case 'low': title = 'Low risk: No single contributor dominates the codebase'; break
    default: title = 'Unknown: Not enough recent activity to assess'
  }
  if (contributors6m.value) title += ` (${contributors6m.value} unique contributors)`
  return title
})

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}

</script>

<template>
  <tr v-if="hasActivity">
    <th scope="row">Activity</th>
    <td>
      <div class="activity-summary">
        <div v-if="commits" class="activity-item">
          <i class="iconoir-git-commit"></i>
          <span class="activity-label">Commits:</span>
          <SparklineChart :values="commits" />
          <span class="activity-value sparkline-total">{{ commitsTotal }}</span>
        </div>
        <div v-if="contributors" class="activity-item">
          <i class="iconoir-community"></i>
          <span class="activity-label">Contributors:</span>
          <SparklineChart :values="contributors" color-class="contributors-sparkline" />
          <span v-if="contributors6m" class="activity-value sparkline-total">{{ contributors6m }}</span>
          <span v-if="contributorsTotal" class="activity-value contributors-total">({{ contributorsTotal }} total)</span>
        </div>
        <div v-if="createdAt" class="activity-item">
          <i class="iconoir-calendar"></i>
          <span class="activity-label">Created:</span>
          <span class="activity-value">{{ createdDate }}</span>
        </div>
        <div v-if="status" class="activity-item">
          <i class="iconoir-info-circle"></i>
          <span class="activity-label">Status:</span>
          <router-link :class="`activity-value status-${status}`" :to="filterUrl('activity/status', status)">
            {{ status }}
          </router-link>
        </div>
        <div v-if="busFactor" class="activity-item">
          <i class="iconoir-warning-triangle"></i>
          <span class="activity-label">Bus Factor:</span>
          <router-link
            :class="`activity-value bus-factor-${busFactor}`"
            :to="filterUrl('activity/busFactor', busFactor)"
            :title="busFactorTitle"
          >
            {{ busFactor }}
          </router-link>
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

.activity-value.status-abandoned {
  color: #dc2626;
  font-weight: 700;
}

.activity-value.status-bot-only {
  color: #f59e0b;
  font-style: italic;
}

.activity-value.status-archived {
  color: #6b7280;
  font-weight: 600;
  text-decoration: line-through;
}

.activity-value.bus-factor-high {
  color: #dc2626;
  font-weight: 700;
}

.activity-value.bus-factor-medium {
  color: #f59e0b;
  font-weight: 600;
}

.sparkline-total {
  margin-left: 6px;
  font-size: 0.85em;
  color: var(--muted-color);
}

.contributors-total {
  margin-left: 4px;
  font-size: 0.8em;
  font-weight: 400;
  color: var(--muted-color);
  opacity: 0.8;
}
</style>
