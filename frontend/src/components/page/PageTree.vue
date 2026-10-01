<script>
import { reactive } from 'vue'

// What the user opened or closed by hand, per menu name: one state for all tree levels (the
// recursive component instances must not keep their own copies), remembered per browser.
// Menus without a choice follow the default in `isOpen`.
const STORAGE_KEY = 'archsight.pageTree.state'

function loadChoices() {
  try {
    const value = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}')
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {}
  } catch {
    return {}
  }
}

const choices = reactive(loadChoices())

function persist() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(choices))
  } catch {
    // storage unavailable, keep the state in memory only
  }
}
</script>

<script setup>
import { computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import '../../css/page.css'

const props = defineProps({
  nodes: Array,
  root: { type: Boolean, default: true },
})

const route = useRoute()

const activeName = computed(() => (route.name === 'page' ? route.params.name : null))

function contains(node, name) {
  return (node.children || []).some(
    (c) => (c.type === 'page' && c.name === name) || (c.type === 'menu' && contains(c, name)),
  )
}

// By default the top level is open (so the tree is never a single closed row) and so is the path
// to the page being read; everything else is closed. What the user chose by hand wins.
function isOpen(node) {
  if (node.name in choices) return choices[node.name]
  return props.root || (activeName.value !== null && contains(node, activeName.value))
}

function toggle(node) {
  choices[node.name] = !isOpen(node)
  persist()
}

// Arriving on a page shows it: menus on its path that were closed by hand open again
watch(activeName, (name) => {
  if (name === null) return
  let changed = false
  for (const node of props.nodes) {
    if (node.type === 'menu' && choices[node.name] === false && contains(node, name)) {
      delete choices[node.name]
      changed = true
    }
  }
  if (changed) persist()
}, { immediate: true })
</script>

<template>
  <ul class="page-tree" :role="root ? 'tree' : 'group'" :aria-label="root ? 'Pages' : undefined">
    <li
      v-for="node in props.nodes"
      :key="`${node.type}:${node.name}`"
      role="treeitem"
      :aria-expanded="node.type === 'menu' ? isOpen(node) : undefined"
      :aria-selected="node.type === 'page' ? activeName === node.name : undefined"
    >
      <template v-if="node.type === 'menu'">
        <button type="button" class="row menu-toggle" @click="toggle(node)">
          <i class="chevron iconoir-nav-arrow-right" :class="{ open: isOpen(node) }" aria-hidden="true"></i>
          <span>{{ node.title }}</span>
        </button>
        <PageTree v-if="isOpen(node)" :nodes="node.children" :root="false" />
      </template>
      <router-link
        v-else
        class="row"
        :to="{ name: 'page', params: { name: node.name } }"
        :aria-current="activeName === node.name ? 'page' : undefined"
      >
        <span class="chevron-space" aria-hidden="true"></span>
        <span>{{ node.title }}</span>
      </router-link>
    </li>
  </ul>
</template>

<style scoped>
/* Rows share the Kinds list's font size and rhythm. Every row reserves a chevron column so
   labels of menus and pages line up at each level. */
.page-tree {
  list-style: none;
  margin: 0;
  padding: 0;
}

/* Pico turns [role=group] into an inline button group; a nested tree level is a plain list */
.page-tree[role='group'] {
  display: block;
  width: auto;
  margin-bottom: 0;
  box-shadow: none;
}

.page-tree[role='group'] > li {
  width: auto;
  margin-left: 0;
  border-radius: 0;
}

/* guide line under the parent's chevron shows how deep a row sits */
.page-tree .page-tree {
  margin-left: 0.55rem;
  border-left: 1px solid var(--wiki-line);
}

.page-tree li {
  margin: 0;
  padding: 0;
}

.row {
  display: flex;
  align-items: center;
  gap: 0.25rem;
  width: calc(100% + 1rem);
  margin: 0 -0.5rem 1px;
  padding: 0.2rem 0.5rem;
  border: 0;
  border-left: 2px solid transparent;
  border-radius: 0 4px 4px 0;
  background: none;
  box-shadow: none;
  color: inherit;
  font-size: 0.85em;
  line-height: 1.3;
  text-align: left;
  text-decoration: none;
  cursor: pointer;
}

.page-tree .page-tree .row {
  width: calc(100% + 0.5rem);
  margin-left: 0;
}

.row:hover {
  background: var(--wiki-tint);
}

.row:focus-visible {
  outline: 2px solid var(--wiki-accent);
  outline-offset: -2px;
}

.menu-toggle {
  font-weight: 600;
}

.chevron,
.chevron-space {
  flex: 0 0 1.1em;
  width: 1.1em;
  font-size: 1em;
  color: var(--pico-muted-color);
}

.chevron {
  transition: transform 120ms ease;
}

.chevron.open {
  transform: rotate(90deg);
}

.row[aria-current='page'] {
  border-left-color: var(--wiki-accent);
  background: var(--wiki-tint);
  color: var(--wiki-accent);
  font-weight: 600;
}

@media (prefers-reduced-motion: reduce) {
  .chevron {
    transition: none;
  }
}
</style>
