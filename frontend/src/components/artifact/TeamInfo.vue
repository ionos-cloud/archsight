<script setup>
import { computed } from 'vue'
import SparklineChart from '../SparklineChart.vue'

const props = defineProps({ annotations: Object, instance: Object })

const lead = computed(() => props.annotations['team/lead'])
const members = computed(() => props.annotations['team/members'])
const teamSize = computed(() => props.annotations['team/size'])
const leadSize = computed(() => props.annotations['team/lead/size'])
const jiraKey = computed(() => props.annotations['team/jira'])
const jiraUrl = computed(() => props.annotations['jira/projectUrl'])
const jiraCreated = computed(() => props.annotations['jira/issues/created'])
const jiraResolved = computed(() => props.annotations['jira/issues/resolved'])
const isTeam = computed(() => props.instance?.kind === 'BusinessActor')

const ownedQuery = computed(() => {
  const name = props.instance?.name || ''
  return `kind in ("ApplicationService", "ApplicationComponent") & ~> $(TechnologyArtifact: -{maintainedBy}> "${name}")`
})

const membersList = computed(() => {
  if (!members.value) return []
  return members.value.split(/,|\n/).map(m => m.trim()).filter(Boolean)
})

function extractEmail(str) {
  const match = str.match(/<([^>]+@[^>]+)>/)
  return match ? match[1] : null
}

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}

function searchUrl(query) {
  return { name: 'search', query: { q: query } }
}

// Jira metrics
const jiraCreatedTotal = computed(() => {
  if (!jiraCreated.value) return 0
  return jiraCreated.value.split(',').map(Number).reduce((a, b) => a + b, 0)
})
const jiraResolvedTotal = computed(() => {
  if (!jiraResolved.value) return 0
  return jiraResolved.value.split(',').map(Number).reduce((a, b) => a + b, 0)
})
const jiraCreatedValues = computed(() => jiraCreated.value ? jiraCreated.value.split(',').map(Number) : [])
const jiraResolvedValues = computed(() => jiraResolved.value ? jiraResolved.value.split(',').map(Number) : [])
const backlogChange = computed(() => {
  const ca = jiraCreatedValues.value.length ? jiraCreatedTotal.value / jiraCreatedValues.value.length : 0
  const ra = jiraResolvedValues.value.length ? jiraResolvedTotal.value / jiraResolvedValues.value.length : 0
  return ca - ra
})
const trendClass = computed(() => {
  const bc = backlogChange.value
  return bc < -1 ? 'positive' : bc > 1 ? 'negative' : 'neutral'
})
</script>

<template>
  <tr v-if="isTeam">
    <th scope="row">Owned Services</th>
    <td>
      <router-link class="badge badge-info" :to="searchUrl(ownedQuery)">
        Show ApplicationServices &amp; Components
      </router-link>
    </td>
  </tr>

  <tr v-if="jiraKey && jiraUrl">
    <th scope="row">Jira Project</th>
    <td>
      <div class="jira-info">
        <a class="badge badge-info" :href="jiraUrl" target="_blank">{{ jiraKey }}</a>
        <template v-if="jiraCreated || jiraResolved">
          <div class="jira-metric">
            <span class="jira-metric-label">Created (6m):</span>
            <SparklineChart :values="jiraCreated" type="created" color-class="jira-created-sparkline" />
            <span class="jira-metric-total">{{ jiraCreatedTotal }}</span>
          </div>
          <div class="jira-metric">
            <span class="jira-metric-label">Resolved (6m):</span>
            <SparklineChart :values="jiraResolved" type="resolved" color-class="jira-resolved-sparkline" />
            <span class="jira-metric-total">{{ jiraResolvedTotal }}</span>
          </div>
          <div :class="['jira-trend', `jira-trend-${trendClass}`]">
            <i v-if="trendClass === 'positive'" class="iconoir-arrow-down-circle"></i>
            <i v-else-if="trendClass === 'negative'" class="iconoir-arrow-up-circle"></i>
            <i v-else class="iconoir-minus-circle"></i>
            <span class="jira-trend-text">{{ backlogChange > 0 ? '+' : '' }}{{ backlogChange.toFixed(1) }}/mo</span>
          </div>
        </template>
      </div>
    </td>
  </tr>

  <tr v-if="lead">
    <th scope="row">Team Lead</th>
    <td>
      <a v-if="extractEmail(lead)" class="team-value" :href="`mailto:${extractEmail(lead)}`">{{ lead }}</a>
      <span v-else class="team-value">{{ lead }}</span>
    </td>
  </tr>

  <tr v-if="teamSize || leadSize">
    <th scope="row">Team Stats</th>
    <td>
      <div class="team-stats">
        <div v-if="leadSize" class="team-stat-item">
          <span class="team-stat-value">{{ leadSize }}</span>
          <span class="team-stat-label">leads</span>
        </div>
        <div v-if="teamSize" class="team-stat-item">
          <span class="team-stat-value">{{ teamSize }}</span>
          <span class="team-stat-label">members</span>
        </div>
      </div>
    </td>
  </tr>

  <tr v-if="members">
    <th scope="row">Team Members</th>
    <td>
      <div class="team-members">
        <template v-for="member in membersList" :key="member">
          <a v-if="extractEmail(member)" class="team-member" :href="`mailto:${extractEmail(member)}`">{{ member }}</a>
          <span v-else class="team-member">{{ member }}</span>
        </template>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.team-stats {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  padding: 8px 12px;
  background-color: var(--card-background-color);
  border-radius: 6px;
  border: 1px solid var(--muted-border-color);
}

.team-stat-item {
  display: flex;
  align-items: baseline;
  gap: 6px;
}

.team-stat-value {
  font-size: 1.5em;
  font-weight: 600;
  color: var(--color);
}

.team-stat-label {
  color: var(--muted-color);
  font-size: 0.9em;
}

.team-value {
  color: var(--color);
}

a.team-value {
  color: var(--primary);
  text-decoration: none;
}

a.team-value:hover {
  text-decoration: underline;
}

.team-members {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.team-member {
  color: var(--color);
}

a.team-member {
  color: var(--primary);
  text-decoration: none;
}

a.team-member:hover {
  text-decoration: underline;
}

/* Jira info */
.jira-info {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}

.jira-metric {
  display: flex;
  align-items: center;
  gap: 6px;
}

.jira-metric-label {
  font-size: 0.85em;
  color: var(--muted-color);
}

.jira-metric-total {
  font-size: 0.85em;
  font-weight: 600;
  color: var(--color);
}

.jira-trend {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 0.85em;
  cursor: help;
}

.jira-trend i {
  font-size: 1em;
}

.jira-trend-text {
  font-weight: 600;
}

.jira-trend-positive i,
.jira-trend-positive .jira-trend-text {
  color: #10b981;
}

.jira-trend-negative i,
.jira-trend-negative .jira-trend-text {
  color: #ef4444;
}

.jira-trend-neutral i,
.jira-trend-neutral .jira-trend-text {
  color: var(--muted-color);
}

@media (prefers-color-scheme: dark) {
  .jira-trend-positive i,
  .jira-trend-positive .jira-trend-text {
    color: #34d399;
  }
  .jira-trend-negative i,
  .jira-trend-negative .jira-trend-text {
    color: #f87171;
  }
}
</style>
