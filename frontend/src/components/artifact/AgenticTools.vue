<script setup>
import { computed } from 'vue'

const props = defineProps({ annotations: Object, kind: String })

const tools = computed(() => (props.annotations['agentic/tools'] || 'none').split(',').map(t => t.trim()))
const hasTools = computed(() => tools.value[0] !== 'none')

const allTools = [
  { key: 'claude', icon: 'iconoir-brain', name: 'Claude', description: 'Anthropic Claude API' },
  { key: 'cursor', icon: 'iconoir-edit-pencil', name: 'Cursor', description: 'AI code editor' },
  { key: 'aider', icon: 'iconoir-terminal', name: 'Aider', description: 'CLI pair programmer' },
  { key: 'github-copilot', icon: 'iconoir-github', name: 'GitHub Copilot', description: 'GitHub AI assistant' },
  { key: 'agents', icon: 'iconoir-cpu-warning', name: 'Custom Agents', description: 'Custom AI agents' },
]

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}
</script>

<template>
  <template v-if="hasTools">
    <tr>
      <th scope="row" colspan="2">
        <i class="iconoir-cpu"></i> AI Coding Assistants
      </th>
    </tr>
    <tr>
      <td class="info-section-cell" colspan="2">
        <div class="agentic-tools">
          <router-link
            v-for="tool in allTools"
            :key="tool.key"
            class="tool-item"
            :class="{ 'not-implemented': !tools.includes(tool.key) }"
            :to="filterUrl('agentic/tools', tool.key)"
          >
            <div class="tool-item-header">
              <input type="checkbox" :checked="tools.includes(tool.key)" disabled />
              <i :class="[tool.icon, tools.includes(tool.key) ? 'implemented' : 'not-implemented']"></i>
              <strong>{{ tool.name }}</strong>
            </div>
            <div class="tool-item-description">{{ tool.description }}</div>
          </router-link>
        </div>
      </td>
    </tr>
  </template>
</template>

<style scoped>
.agentic-tools {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
}

.tool-item {
  padding: 0.75rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 6px;
  transition: opacity 0.2s ease, border-color 0.2s ease;
  text-decoration: none;
  color: var(--color);
  display: block;
}

.tool-item:hover {
  border-color: var(--primary);
}

.tool-item.not-implemented {
  opacity: 0.4;
}

.tool-item-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.25rem;
}

.tool-item-header input[type="checkbox"] {
  margin: 0;
  pointer-events: none;
}

.tool-item-header i {
  font-size: 1.2em;
}

.tool-item-header i.implemented {
  color: var(--primary);
}

.tool-item-header i.not-implemented {
  color: var(--muted-color);
}

.tool-item-description {
  font-size: 0.85em;
  color: var(--muted-color);
}
</style>
