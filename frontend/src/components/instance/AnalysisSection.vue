<script setup>
const props = defineProps({ section: Object })

const messageIcons = { error: 'xmark-circle', warning: 'warning-triangle', info: 'info-circle' }
</script>

<template>
  <div v-if="section.type === 'heading'" class="analysis-heading" :class="'level-' + section.level">
    {{ section.text }}
  </div>
  <div v-else-if="section.type === 'text'" class="analysis-text" v-html="section.content"></div>
  <div v-else-if="section.type === 'message'" class="analysis-message" :class="'message-' + section.level">
    <i :class="`iconoir-${messageIcons[section.level] || 'info-circle'}`"></i> {{ section.message }}
  </div>
  <div v-else-if="section.type === 'table'" class="analysis-table-wrapper">
    <table>
      <thead><tr><th v-for="h in section.headers" :key="h">{{ h }}</th></tr></thead>
      <tbody><tr v-for="(row, ri) in section.rows" :key="ri"><td v-for="(cell, ci) in row" :key="ci">{{ cell }}</td></tr></tbody>
    </table>
  </div>
  <ul v-else-if="section.type === 'list'" class="analysis-list">
    <li v-for="(item, i) in section.items" :key="i">{{ item }}</li>
  </ul>
  <pre v-else-if="section.type === 'code'" class="code"><code :class="section.lang ? 'language-' + section.lang : ''">{{ section.content }}</code></pre>
</template>

<style scoped>
.analysis-heading {
  font-weight: 600;
  margin: 1rem 0 0.5rem 0;
}

.analysis-heading.level-0 {
  font-size: 1.25em;
  border-bottom: 1px solid var(--muted-border-color);
  padding-bottom: 0.25rem;
}

.analysis-heading.level-1 { font-size: 1.1em; }
.analysis-heading.level-2 { font-size: 1em; }

.analysis-text {
  margin: 0.5rem 0;
}

:deep(.analysis-text p) {
  margin: 0;
}

.analysis-message {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem;
  margin: 0.5rem 0;
  border-radius: 4px;
}

.analysis-message i { margin-top: 0.15rem; }

.analysis-message.message-info {
  background-color: rgba(59, 130, 246, 0.1);
  border: 1px solid rgba(59, 130, 246, 0.3);
  color: #3b82f6;
}

.analysis-message.message-warning {
  background-color: rgba(245, 158, 11, 0.1);
  border: 1px solid rgba(245, 158, 11, 0.3);
  color: #f59e0b;
}

.analysis-message.message-error {
  background-color: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  color: #ef4444;
}

.analysis-table-wrapper {
  margin: 0.75rem 0;
  overflow-x: auto;
}

.analysis-list {
  margin: 0.5rem 0;
  padding-left: 1.5rem;
}

.analysis-list li { margin: 0.25rem 0; }
</style>
