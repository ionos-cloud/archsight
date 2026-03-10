<script setup>
import { ref, watch, computed } from 'vue'
import { useRoute } from 'vue-router'
import { getKindFilters } from '../../api/client.js'

const props = defineProps({
  kinds: Object,
})

const route = useRoute()

const currentKind = computed(() => route.params.kind)
const filters = ref([])

function isCurrentKind(kindName) {
  return currentKind.value === kindName
}

watch(currentKind, async (kind) => {
  if (!kind) { filters.value = []; return }
  try {
    filters.value = await getKindFilters(kind)
  } catch {
    filters.value = []
  }
}, { immediate: true })

function filterQuery(key, value) {
  const q = `${currentKind.value}: ${key} == "${value}"`
  return `/search?q=${encodeURIComponent(q)}`
}
</script>

<template>
  <aside class="sidebar">
    <div class="sidebar-section">
      <h4 class="sidebar-heading">
        <i class="iconoir-folder"></i>
        Kinds
      </h4>
      <nav class="kind-filter">
        <ul>
          <template v-if="kinds">
            <li v-for="k in kinds.kinds" :key="k.kind">
              <router-link
                :to="{ name: 'kind', params: { kind: k.kind } }"
                :aria-current="isCurrentKind(k.kind) ? 'page' : undefined"
              >
                <span class="kind-name">{{ k.kind }}</span>
                <span class="kind-count">{{ k.instance_count }}</span>
              </router-link>
            </li>
          </template>
          <li v-else>
            <span class="kind-name">Loading...</span>
          </li>
        </ul>
      </nav>
    </div>
    <div v-if="filters.length" class="sidebar-section">
      <h4 class="sidebar-heading">
        <i class="iconoir-filter"></i>
        Filters
      </h4>
      <nav class="annotation-filter">
        <div v-for="f in filters" :key="f.key" class="filter-group">
          <div class="filter-label" :title="f.description">{{ f.title }}</div>
          <div class="filter-chips">
            <router-link
              v-for="val in f.values"
              :key="val"
              class="filter-chip"
              :to="filterQuery(f.key, val)"
            >
              {{ val }}
            </router-link>
          </div>
        </div>
      </nav>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.sidebar-section {
  padding-bottom: 16px;
  margin-bottom: 16px;
}

.sidebar-section:not(:last-child) {
  border-bottom: 1px solid var(--muted-border-color);
}

.sidebar-heading {
  margin-bottom: 8px;
}

.kind-filter ul,
.instance-list ul {
  padding: 0;
  margin: 0;
}

.kind-filter li,
.instance-list li {
  padding: 0;
  margin: 0;
}

.kind-filter a,
.instance-list a {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 2px;
  font-size: 0.85em;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  text-decoration: none;
}

.kind-filter a[aria-current="page"],
.instance-list a[aria-current="page"] {
  background-color: var(--primary);
  color: var(--primary-inverse);
}

.kind-count {
  font-size: 0.85em;
  padding: 2px 6px;
  border-radius: 10px;
  min-width: 24px;
  text-align: center;
  opacity: 0.7;
}

.kind-filter a[aria-current="page"] .kind-count {
  opacity: 1;
}

.filter-group {
  margin-bottom: 0.5rem;
}

.filter-group:last-child {
  margin-bottom: 0;
}

.filter-label {
  font-size: 0.75em;
  font-weight: 600;
  color: var(--muted-color);
  text-transform: uppercase;
  margin-bottom: 0.25rem;
  padding: 0;
}

.filter-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.25rem;
}

.filter-chip {
  display: inline-block;
  font-size: 0.75em;
  padding: 0.2rem 0.5rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 12px;
  text-decoration: none;
  color: var(--color);
  transition: all 0.2s ease;
}

.filter-chip:hover {
  background-color: var(--primary);
  color: var(--primary-inverse);
  border-color: var(--primary);
}

@media all and (min-width: 800px) {
  .sidebar {
    width: clamp(250px, 20vw, 400px);
    flex-shrink: 0;
  }
}
</style>
