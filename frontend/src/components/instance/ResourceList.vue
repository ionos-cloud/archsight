<script setup>
import { computed, ref, onMounted, onBeforeUnmount, watch } from 'vue'
import { timeAgo } from '../../composables/useFormatting.js'

const props = defineProps({
  instances: { type: Array, required: true },
  omitKind: { type: Boolean, default: false },
  fields: { type: Array, default: null },
  total: { type: Number, default: 0 },
  loadingMore: { type: Boolean, default: false },
})

const emit = defineEmits(['load-more'])

const sentinel = ref(null)
let observer = null

const hasMore = computed(() => props.total > props.instances.length)

function setupObserver() {
  if (observer) observer.disconnect()
  if (!sentinel.value) return
  observer = new IntersectionObserver((entries) => {
    if (entries[0].isIntersecting && hasMore.value && !props.loadingMore) {
      emit('load-more')
    }
  }, { rootMargin: '200px' })
  observer.observe(sentinel.value)
}

onMounted(setupObserver)
watch(sentinel, setupObserver)
onBeforeUnmount(() => { if (observer) observer.disconnect() })

const useTable = computed(() => props.fields && props.fields.length > 0)

const fieldColumns = computed(() => {
  if (!props.fields) return []
  return props.fields.map(f => {
    const segments = f.split('/')
    let title
    if (segments.length >= 2) {
      title = `${segments[segments.length - 2]} ${segments[segments.length - 1]}`
    } else {
      title = segments[segments.length - 1]
    }
    title = title.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase())
    return { key: f, title }
  })
})

function annotationValue(inst, key) {
  const annotations = inst.annotations || {}
  return annotations[key] ?? null
}

function isTimeField(key) {
  return /at$/i.test(key) || /date$/i.test(key) || /time$/i.test(key)
}
</script>

<template>
  <p v-if="!instances.length" class="empty-state"><i>No resources found</i></p>

  <table v-else-if="useTable" class="resource-list-table">
    <thead>
      <tr>
        <th class="col-name">Name</th>
        <th v-if="!omitKind" class="col-kind">Kind</th>
        <th v-for="col in fieldColumns" :key="col.key" class="col-annotation">{{ col.title }}</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="inst in instances" :key="inst.name" class="resource-list-row">
        <td class="col-name">
          <router-link
            class="instance-name"
            :to="{ name: 'instance', params: { kind: inst.kind, instance: inst.name } }"
          >
            <i v-if="inst.icon" :class="`iconoir-${inst.icon} icon-${inst.layer}`"></i>
            {{ inst.name }}
          </router-link>
        </td>
        <td v-if="!omitKind" class="col-kind">
          <span class="instance-kind">{{ inst.kind }}</span>
        </td>
        <td v-for="col in fieldColumns" :key="col.key" class="col-annotation">
          <template v-if="annotationValue(inst, col.key) != null">
            <span v-if="isTimeField(col.key)" :title="annotationValue(inst, col.key)">
              {{ timeAgo(annotationValue(inst, col.key)) }}
            </span>
            <template v-else>{{ annotationValue(inst, col.key) }}</template>
          </template>
          <span v-else class="empty-value">&mdash;</span>
        </td>
      </tr>
    </tbody>
  </table>

  <ul v-else class="search-instance-list">
    <li v-for="inst in instances" :key="inst.name" class="search-instance-item">
      <div class="instance-main">
        <router-link
          class="instance-name"
          :to="{ name: 'instance', params: { kind: inst.kind, instance: inst.name } }"
        >
          <i v-if="inst.icon" :class="`iconoir-${inst.icon} icon-${inst.layer}`"></i>
          {{ inst.name }}
        </router-link>
        <span v-if="!omitKind" class="instance-kind">{{ inst.kind }}</span>
      </div>
    </li>
  </ul>

  <div v-if="hasMore" ref="sentinel" class="load-more-sentinel">
    <small v-if="loadingMore">Loading more…</small>
  </div>
</template>

<style scoped>
.search-instance-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.search-instance-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 8px;
  margin-bottom: 2px;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 4px;
  transition: border-color 0.15s ease;
}

.search-instance-item:hover {
  border-color: var(--primary);
}

.instance-main {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1;
}

.instance-name {
  font-weight: 600;
  font-size: 1em;
  color: var(--primary);
  text-decoration: none;
}

.instance-name:hover {
  text-decoration: underline;
}

.instance-kind {
  font-size: 0.85em;
  color: var(--muted-color);
  padding: 2px 8px;
  background-color: var(--code-background-color);
  border-radius: 4px;
}

.resource-list-table {
  width: 100%;
  border-collapse: collapse;
  margin: 0;
}

.resource-list-table thead th {
  text-align: left;
  padding: 8px 12px;
  font-weight: 600;
  font-size: 0.85em;
  color: var(--muted-color);
  border-bottom: 2px solid var(--muted-border-color);
  background-color: var(--card-background-color);
}

.resource-list-table tbody tr {
  border-bottom: 1px solid var(--muted-border-color);
  transition: background-color 0.15s ease;
}

.resource-list-table tbody tr:hover {
  background-color: var(--card-background-color);
}

.resource-list-table td {
  padding: 8px 12px;
  vertical-align: middle;
}

.resource-list-table .col-name {
  min-width: 200px;
}

.resource-list-table .col-kind {
  white-space: nowrap;
}

.resource-list-table .col-annotation {
  color: var(--color);
  font-size: 0.9em;
}

.resource-list-table .empty-value {
  color: var(--muted-color);
}

.resource-list-table .instance-name {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
</style>
