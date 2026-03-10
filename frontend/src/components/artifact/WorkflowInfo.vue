<script setup>
import { computed } from 'vue'

const props = defineProps({ annotations: Object, kind: String })

const platforms = computed(() => (props.annotations['workflow/platforms'] || 'none').split(',').map(t => t.trim()))
const types = computed(() => (props.annotations['workflow/types'] || 'none').split(',').map(t => t.trim()))
const hasWorkflow = computed(() => platforms.value[0] !== 'none' || types.value[0] !== 'none')
const hasGenericTest = computed(() => types.value.includes('test'))

function filterUrl(key, value) {
  return { name: 'search', query: { q: `${key} == "${value}"` } }
}

function has(list, item) {
  return list.includes(item)
}
</script>

<template>
  <template v-if="hasWorkflow">
    <tr>
      <th scope="row">CI/CD Platforms</th>
      <td>
        <div class="workflow-platforms">
          <router-link class="workflow-platform-item" :to="filterUrl('workflow/platforms', 'github-actions')">
            <input type="checkbox" disabled :checked="has(platforms, 'github-actions')" />
            <label>GitHub Actions</label>
          </router-link>
          <router-link class="workflow-platform-item" :to="filterUrl('workflow/platforms', 'gitlab-ci')">
            <input type="checkbox" disabled :checked="has(platforms, 'gitlab-ci')" />
            <label>GitLab CI</label>
          </router-link>
          <router-link class="workflow-platform-item" :to="filterUrl('workflow/platforms', 'makefile')">
            <input type="checkbox" disabled :checked="has(platforms, 'makefile')" />
            <label>Makefile</label>
          </router-link>
        </div>
      </td>
    </tr>
    <tr>
      <td class="info-section-cell" colspan="2">
        <details open>
          <summary><strong>Workflow Types</strong></summary>
          <div class="workflow-types">
            <div>
              <div class="workflow-category">
                <strong>Build &amp; Deploy</strong>
                <ul>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'build')" />
                    <router-link :to="filterUrl('workflow/types', 'build')">Build</router-link>
                  </li>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'deploy')" />
                    <router-link :to="filterUrl('workflow/types', 'deploy')">Deploy</router-link>
                  </li>
                </ul>
              </div>
              <div class="workflow-category">
                <strong>Testing</strong>
                <ul>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'test')" />
                    <router-link :to="filterUrl('workflow/types', 'test')">Test (generic)</router-link>
                  </li>
                  <li :class="{ 'grayed-out': hasGenericTest }">
                    <input type="checkbox" disabled :checked="has(types, 'unit-test')" />
                    <router-link :to="filterUrl('workflow/types', 'unit-test')">Unit Tests</router-link>
                  </li>
                  <li :class="{ 'grayed-out': hasGenericTest }">
                    <input type="checkbox" disabled :checked="has(types, 'integration-test')" />
                    <router-link :to="filterUrl('workflow/types', 'integration-test')">Integration Tests</router-link>
                  </li>
                  <li :class="{ 'grayed-out': hasGenericTest }">
                    <input type="checkbox" disabled :checked="has(types, 'smoke-test')" />
                    <router-link :to="filterUrl('workflow/types', 'smoke-test')">Smoke Tests</router-link>
                  </li>
                </ul>
              </div>
              <div class="workflow-category">
                <strong>Quality &amp; Security</strong>
                <ul>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'lint')" />
                    <router-link :to="filterUrl('workflow/types', 'lint')">Linting</router-link>
                  </li>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'security-scan')" />
                    <router-link :to="filterUrl('workflow/types', 'security-scan')">Security Scan</router-link>
                  </li>
                </ul>
              </div>
              <div class="workflow-category">
                <strong>Automation</strong>
                <ul>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'dependency-update')" />
                    <router-link :to="filterUrl('workflow/types', 'dependency-update')">Dependency Updates</router-link>
                  </li>
                  <li>
                    <input type="checkbox" disabled :checked="has(types, 'ticket-creation')" />
                    <router-link :to="filterUrl('workflow/types', 'ticket-creation')">Ticket Creation</router-link>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </details>
      </td>
    </tr>
  </template>
</template>

<style scoped>
.workflow-platforms {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 0.5rem;
}

.workflow-platform-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 6px;
  text-decoration: none;
  color: var(--color);
  transition: border-color 0.2s ease;
}

.workflow-platform-item:hover {
  border-color: var(--primary);
}

.workflow-platform-item input[type="checkbox"] {
  margin: 0;
  pointer-events: none;
}

.workflow-types ul {
  list-style: none;
  padding-left: 0;
  margin: 0.25rem 0 0 0;
}

.workflow-types li {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.workflow-types li input[type="checkbox"] {
  margin: 0;
  pointer-events: none;
}

.workflow-types li a {
  text-decoration: none;
  color: var(--color);
  transition: color 0.2s ease;
}

.workflow-types li a:hover {
  color: var(--primary);
  text-decoration: underline;
}

.workflow-types li.grayed-out {
  opacity: 0.4;
}

.workflow-types {
  padding-left: 1rem;
  margin-top: 0.5rem;
}

.workflow-types>div {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.5rem;
}

.workflow-category strong {
  display: block;
  margin-bottom: 0.25rem;
}
</style>
