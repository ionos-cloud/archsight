<script setup>
import { computed } from 'vue'
import { toEuro, aiAdjustedEstimate } from '../../composables/useFormatting.js'

const props = defineProps({ annotations: Object })

const cost = computed(() => aiAdjustedEstimate('cost', props.annotations['scc/estimatedCost']))
const schedule = computed(() => aiAdjustedEstimate('schedule', props.annotations['scc/estimatedScheduleMonths']))
const people = computed(() => aiAdjustedEstimate('team', props.annotations['scc/estimatedPeople']))
const hasEstimate = computed(() => cost.value != null || schedule.value != null || people.value != null)
</script>

<template>
  <tr v-if="hasEstimate">
    <th scope="row">
      Project Estimate
      <span class="estimate-note" title="Estimates adjusted for &euro;80k salary and AI-assisted development (3x productivity)">
        <i class="iconoir-info-circle"></i>
      </span>
    </th>
    <td>
      <div class="project-estimate">
        <div v-if="cost != null" class="estimate-item">
          <i class="iconoir-euro"></i>
          <span class="estimate-label">Cost:</span>
          <span class="estimate-value">{{ toEuro(cost) }}</span>
        </div>
        <div v-if="schedule != null" class="estimate-item">
          <i class="iconoir-calendar"></i>
          <span class="estimate-label">Schedule:</span>
          <span class="estimate-value">{{ schedule.toFixed(1) }} months</span>
        </div>
        <div v-if="people != null" class="estimate-item">
          <i class="iconoir-group"></i>
          <span class="estimate-label">Team:</span>
          <span class="estimate-value">{{ people }} people</span>
        </div>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.project-estimate {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  padding: 4px 0;
}

.estimate-item {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.estimate-item i {
  font-size: 1.2em;
  color: var(--primary);
}

.estimate-label {
  color: var(--muted-color);
  font-size: 0.9em;
}

.estimate-value {
  font-weight: 600;
  color: var(--color);
}

.estimate-note {
  margin-left: 0.5rem;
  color: var(--muted-color);
  cursor: help;
}

.estimate-note i {
  font-size: 0.875rem;
}
</style>
