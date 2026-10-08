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
  margin: 1rem 0 0.4rem 0;
}

.analysis-heading.level-0 {
  font-size: var(--fs-md);
  border-bottom: 1px solid var(--line);
  padding-bottom: 0.25rem;
}

.analysis-heading.level-1 { font-size: var(--fs-md); }
.analysis-heading.level-2 { font-size: 1em; }

.analysis-text {
  margin: 0.5rem 0;
}

:deep(.analysis-text p) {
  margin: 0;
}

/* a message is a note, not a box: a coloured edge and icon, the text stays in the normal colour */
.analysis-message {
  --msg: #3b82f6;
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  margin: 0.5rem 0;
  padding: 0.15rem 0 0.15rem 0.7rem;
  border-left: 3px solid var(--msg);
}

.analysis-message i {
  margin-top: 0.15rem;
  color: var(--msg);
}

.analysis-message.message-warning { --msg: #f59e0b; }
.analysis-message.message-error { --msg: #ef4444; }

.analysis-table-wrapper {
  margin: 0.5rem 0 0.75rem;
  overflow-x: auto;
}

.analysis-table-wrapper table {
  margin: 0;
  font-size: var(--fs-sm);
}

.analysis-table-wrapper th,
.analysis-table-wrapper td {
  padding: 0.35rem 0.75rem;
}

/* the first column lines up with the text above, the last with the edge */
.analysis-table-wrapper th:first-child,
.analysis-table-wrapper td:first-child { padding-left: 0; }

pre.code {
  margin: 0.5rem 0 0.75rem;
}

.analysis-list {
  margin: 0.5rem 0;
  padding-left: 1.5rem;
  columns: 18rem; /* a long list wraps into columns instead of a tall strip */
}

/* padding, not margin: a margin at the top of a column is dropped and the columns start unevenly */
.analysis-list li { margin: 0; padding: 0.125rem 0; break-inside: avoid; }
</style>
