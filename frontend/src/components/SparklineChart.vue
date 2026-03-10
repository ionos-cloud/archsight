<script setup>
import { computed } from 'vue'

const props = defineProps({
  values: { type: String, required: true },
  type: { type: String, default: 'commits' },
  maxHeight: { type: Number, default: 16 },
  colorClass: { type: String, default: null }
})

const parsedValues = computed(() => {
  if (!props.values || props.values.trim() === '') return []
  return props.values.split(',').map(v => parseInt(v, 10) || 0)
})

const max = computed(() => {
  const m = Math.max(...parsedValues.value)
  return m === 0 ? 1 : m
})

function barHeight(val) {
  return val === 0 ? 0 : Math.max(2, Math.round((val / max.value) * props.maxHeight))
}

const tooltipSuffix = computed(() => {
  switch (props.type) {
    case 'created': return ' issues created'
    case 'resolved': return ' issues resolved'
    default: return ' commits'
  }
})
</script>

<template>
  <div class="activity-sparkline" :class="colorClass">
    <div
      v-for="(val, i) in parsedValues"
      :key="i"
      class="activity-sparkline-bar"
      :class="{ empty: val === 0 }"
      :style="{ height: barHeight(val) + 'px' }"
      :title="val + tooltipSuffix"
    />
  </div>
</template>

<style scoped>
.activity-sparkline {
  display: inline-flex;
  align-items: flex-end;
  gap: 1px;
  height: 20px;
  padding: 2px 4px;
  background-color: var(--card-background-color);
  border-radius: 4px;
  border: 1px solid var(--muted-border-color);
}

.activity-sparkline-bar {
  width: 2px;
  min-height: 2px;
  background-color: #3178c6;
  border-radius: 1px;
  transition: background-color 0.2s ease;
}

.activity-sparkline-bar.empty {
  min-height: 0;
  background-color: transparent;
}

.activity-sparkline-bar:hover {
  background-color: #2563eb;
}

.activity-sparkline-bar.empty:hover {
  background-color: transparent;
}

/* Contributors sparkline - green color */
.contributors-sparkline .activity-sparkline-bar {
  background-color: #10b981;
}
.contributors-sparkline .activity-sparkline-bar:hover {
  background-color: #059669;
}

/* Jira sparkline colors */
.jira-created-sparkline .activity-sparkline-bar {
  background-color: #f59e0b;
}
.jira-created-sparkline .activity-sparkline-bar:hover {
  background-color: #d97706;
}
.jira-resolved-sparkline .activity-sparkline-bar {
  background-color: #10b981;
}
.jira-resolved-sparkline .activity-sparkline-bar:hover {
  background-color: #059669;
}

@media (prefers-color-scheme: dark) {
  .jira-created-sparkline .activity-sparkline-bar {
    background-color: #fbbf24;
  }
  .jira-resolved-sparkline .activity-sparkline-bar {
    background-color: #34d399;
  }
}

/* Small sparkline variant for table cells */
.sparkline-sm {
  height: 28px;
  gap: 2px;
}
.sparkline-sm .activity-sparkline-bar {
  width: 4px;
  border-radius: 1px;
}
</style>
