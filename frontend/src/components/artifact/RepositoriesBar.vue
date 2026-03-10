<script setup>
import { computed } from 'vue'

const props = defineProps({ annotations: Object })

const total = computed(() => parseInt(props.annotations['repository/artifacts/total'] || '0', 10))
const active = computed(() => parseInt(props.annotations['repository/artifacts/active'] || '0', 10))
const abandoned = computed(() => parseInt(props.annotations['repository/artifacts/abandoned'] || '0', 10))
const archived = computed(() => parseInt(props.annotations['repository/artifacts/archived'] || '0', 10))
const highBusFactor = computed(() => parseInt(props.annotations['repository/artifacts/highBusFactor'] || '0', 10))
const hasData = computed(() => total.value > 0)

const activeHealthy = computed(() => active.value - highBusFactor.value)
const other = computed(() => total.value - active.value - abandoned.value - archived.value)

function pct(value) {
  return (value / total.value * 100).toFixed(1)
}

const segments = computed(() => {
  const s = []
  if (activeHealthy.value > 0) s.push({ cls: 'status-active', value: activeHealthy.value, label: 'Active (healthy)' })
  if (highBusFactor.value > 0) s.push({ cls: 'status-high-bus-factor', value: highBusFactor.value, label: 'Active (high bus factor)' })
  if (archived.value > 0) s.push({ cls: 'status-archived', value: archived.value, label: 'Archived' })
  if (other.value > 0) s.push({ cls: 'status-other', value: other.value, label: 'Other' })
  if (abandoned.value > 0) s.push({ cls: 'status-abandoned', value: abandoned.value, label: 'Abandoned' })
  return s
})
</script>

<template>
  <tr v-if="hasData">
    <th scope="row">Repositories</th>
    <td>
      <div class="repository-distribution">
        <div class="repository-total">
          <span class="repository-count">{{ total }}</span>
          <span class="repository-label">repositories</span>
        </div>
        <div class="repository-bar">
          <div
            v-for="seg in segments"
            :key="seg.cls"
            :class="['repository-bar-segment', seg.cls]"
            :style="{ width: pct(seg.value) + '%' }"
            :title="`${seg.label}: ${seg.value} (${pct(seg.value)}%)`"
          ></div>
        </div>
        <div class="repository-legend">
          <div v-for="seg in segments" :key="seg.cls" class="repository-legend-item">
            <div :class="['repository-legend-dot', seg.cls]"></div>
            <span>{{ seg.value }} {{ seg.label.toLowerCase() }}</span>
          </div>
        </div>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.repository-distribution {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 200px;
  padding: 8px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.repository-total {
  display: flex;
  align-items: baseline;
  gap: 6px;
}

.repository-total .repository-count {
  font-size: 1.5em;
  font-weight: 600;
  color: var(--color);
}

.repository-total .repository-label {
  color: var(--muted-color);
  font-size: 0.9em;
}

.repository-bar {
  display: flex;
  height: 8px;
  border-radius: 4px;
  overflow: hidden;
  background-color: var(--muted-border-color);
}

.repository-bar-segment {
  height: 100%;
  min-width: 2px;
}

.repository-bar-segment.status-active { background-color: #10b981; }
.repository-bar-segment.status-high-bus-factor { background-color: #f59e0b; }
.repository-bar-segment.status-abandoned { background-color: #dc2626; }
.repository-bar-segment.status-other { background-color: #6b7280; }
.repository-bar-segment.status-archived { background-color: #9ca3af; }

.repository-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  font-size: 0.85em;
}

.repository-legend-item {
  display: flex;
  align-items: center;
  gap: 4px;
  color: var(--muted-color);
}

.repository-legend-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}

.repository-legend-dot.status-active { background-color: #10b981; }
.repository-legend-dot.status-high-bus-factor { background-color: #f59e0b; }
.repository-legend-dot.status-abandoned { background-color: #dc2626; }
.repository-legend-dot.status-other { background-color: #6b7280; }
.repository-legend-dot.status-archived { background-color: #9ca3af; }

@media (prefers-color-scheme: dark) {
  .repository-bar-segment.status-active,
  .repository-legend-dot.status-active { background-color: #34d399; }
  .repository-bar-segment.status-high-bus-factor,
  .repository-legend-dot.status-high-bus-factor { background-color: #fbbf24; }
  .repository-bar-segment.status-abandoned,
  .repository-legend-dot.status-abandoned { background-color: #f87171; }
  .repository-bar-segment.status-other,
  .repository-legend-dot.status-other { background-color: #9ca3af; }
  .repository-bar-segment.status-archived,
  .repository-legend-dot.status-archived { background-color: #d1d5db; }
}
</style>
