<script setup>
import { ref } from 'vue'
import { useInternalLinks } from '../../composables/useInternalLinks.js'

defineProps({ section: Object })

// table cells, list items and messages come as raw values and as html (`*_html`: inline markdown, [[Kind/Name]]
// links); the links open in the app
const sectionEl = ref(null)
useInternalLinks(sectionEl)

const messageIcons = { error: 'xmark-circle', warning: 'warning-triangle', info: 'info-circle' }
</script>

<template>
  <div v-if="section.type === 'heading'" class="analysis-heading" :class="'level-' + section.level">
    {{ section.text }}
  </div>
  <div v-else-if="section.type === 'text'" ref="sectionEl" class="analysis-text" v-html="section.content"></div>
  <div v-else-if="section.type === 'message'" ref="sectionEl" class="analysis-message" :class="'message-' + section.level">
    <i :class="`iconoir-${messageIcons[section.level] || 'info-circle'}`"></i>
    <span v-if="section.message_html != null" v-html="section.message_html"></span><span v-else>{{ section.message }}</span>
  </div>
  <div v-else-if="section.type === 'table'" ref="sectionEl" class="analysis-table-wrapper">
    <table>
      <thead><tr><th v-for="h in section.headers" :key="h">{{ h }}</th></tr></thead>
      <tbody>
        <tr v-for="(row, ri) in section.rows" :key="ri">
          <template v-for="(cell, ci) in row" :key="ci">
            <td v-if="section.rows_html" v-html="section.rows_html[ri][ci]"></td>
            <td v-else>{{ cell }}</td>
          </template>
        </tr>
      </tbody>
    </table>
  </div>
  <ul v-else-if="section.type === 'list'" ref="sectionEl" class="analysis-list">
    <template v-for="(item, i) in section.items" :key="i">
      <li v-if="section.items_html" v-html="section.items_html[i]"></li>
      <li v-else>{{ item }}</li>
    </template>
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

/* on the analysis page the table has no rules, so the first column lines up with the text above; embedded in a
   page (compact) the table has the cell borders of the page's own tables and keeps their padding (prose.css) */
.analysis-execution:not(.compact) .analysis-table-wrapper th,
.analysis-execution:not(.compact) .analysis-table-wrapper td {
  padding: 0.35rem 0.75rem;
}

.analysis-execution:not(.compact) .analysis-table-wrapper th:first-child,
.analysis-execution:not(.compact) .analysis-table-wrapper td:first-child { padding-left: 0; }

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
