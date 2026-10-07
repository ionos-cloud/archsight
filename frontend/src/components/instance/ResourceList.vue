<script setup>
import { useRouter } from 'vue-router'
import { computed, ref, inject, onMounted, onBeforeUnmount, watch } from 'vue'
import { timeAgo, fieldValue, isIdentityField } from '../../composables/useFormatting.js'
import HighlightList from '../search/HighlightList.vue'

const props = defineProps({
  instances: { type: Array, required: true },
  omitKind: { type: Boolean, default: false },
  fields: { type: Array, default: null },
  total: { type: Number, default: 0 },
  loadingMore: { type: Boolean, default: false },
  // page search: pages link to the wiki page (/pages/<name>) and show their title
  pageLinks: { type: Boolean, default: false },
  // quiet rows (hairlines instead of a box per row), used by the search results
  rows: { type: Boolean, default: false },
})

const emit = defineEmits(['load-more'])

const pageTitles = inject('pageTitles', null)

function isPageLink(inst) {
  return props.pageLinks && inst.kind === 'Page'
}

const router = useRouter()

// the whole table row opens the resource; real links, selections and modified clicks keep their own behaviour
function openRow(inst, event) {
  if (event.target.closest('a') || event.metaKey || event.ctrlKey || event.shiftKey) return
  if (window.getSelection()?.toString()) return
  router.push(linkTo(inst))
}

function linkTo(inst) {
  return isPageLink(inst)
    ? { name: 'page', params: { name: inst.name } }
    : { name: 'instance', params: { kind: inst.kind, instance: inst.name } }
}

function labelOf(inst) {
  return (isPageLink(inst) && pageTitles?.value?.[inst.name]) || inst.name
}

// the file/page name, when it differs from the title shown
function subLabelOf(inst) {
  return isPageLink(inst) && labelOf(inst) !== inst.name ? inst.name : null
}

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
  return props.fields.filter(f => !isIdentityField(f)).map(f => {
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
  return fieldValue(inst, key)
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
      <tr v-for="inst in instances" :key="inst.name" class="resource-list-row" @click="openRow(inst, $event)">
        <td class="col-name">
          <router-link class="instance-name" :to="linkTo(inst)">
            <i v-if="inst.icon" :class="`iconoir-${inst.icon} icon-${inst.layer}`"></i>
            {{ labelOf(inst) }}
          </router-link>
          <span v-if="subLabelOf(inst)" class="instance-sub">{{ subLabelOf(inst) }}</span>
        </td>
        <td v-if="!omitKind" class="col-kind">
          <span v-if="!isPageLink(inst)" class="instance-kind">{{ inst.kind }}</span>
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

  <ul v-else class="search-instance-list" :class="{ rows }">
    <li v-for="inst in instances" :key="inst.name" class="search-instance-item">
      <div class="instance-main">
        <router-link class="instance-name" :to="linkTo(inst)">
          <i v-if="inst.icon" :class="`iconoir-${inst.icon} icon-${inst.layer}`"></i>
          {{ labelOf(inst) }}
        </router-link>
        <span v-if="subLabelOf(inst)" class="instance-sub">{{ subLabelOf(inst) }}</span>
        <span v-if="!omitKind && !isPageLink(inst)" class="instance-kind">{{ inst.kind }}</span>
      </div>
      <HighlightList v-if="inst.highlights?.length" :items="inst.highlights" :kind="inst.kind" />
    </li>
  </ul>

  <div v-if="hasMore" ref="sentinel" class="load-more-sentinel">
    <small v-if="loadingMore">Loading more…</small>
  </div>
</template>

<style scoped>
.instance-sub {
  margin-left: 0.5rem;
  color: var(--pico-muted-color);
  font-size: var(--fs-xs);
}

.search-instance-list {
  list-style: none;
  padding: 0;
  margin: 0;
}

.search-instance-item {
  position: relative;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 8px;
  margin-bottom: 2px;
  background-color: var(--pico-card-background-color);
  border: 1px solid var(--pico-muted-border-color);
  border-radius: 4px;
  transition: border-color 0.15s ease;
}

.search-instance-item:hover {
  border-color: var(--pico-primary);
  background-color: var(--pico-code-background-color);
}

.instance-main {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1;
  min-width: 0;
}

/* quiet rows: a hairline between hits, the hover tint is the only emphasis */
.rows .search-instance-item {
  flex-wrap: wrap;
  gap: 0.25rem 1rem;
  margin: 0;
  padding: 0.5rem 0.25rem;
  background-color: transparent;
  border: 0;
  border-bottom: 1px solid var(--line);
  border-radius: 0;
}

.rows .search-instance-item:hover {
  background-color: var(--tint);
}

.rows .instance-kind {
  padding: 0;
  background: none;
}

.instance-name {
  font-weight: 600;
  font-size: 1em;
  color: var(--pico-primary);
  text-decoration: none;
}

/* stretched link: the whole row is the click target, the name stays the accessible link */
.search-instance-item .instance-name::after {
  content: '';
  position: absolute;
  inset: 0;
}

.instance-kind {
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
  padding: 2px 8px;
  background-color: var(--pico-code-background-color);
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
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
  border-bottom: 2px solid var(--pico-muted-border-color);
  background-color: var(--pico-card-background-color);
}

.resource-list-table tbody tr {
  border-bottom: 1px solid var(--pico-muted-border-color);
  transition: background-color 0.15s ease;
}

.resource-list-table tbody tr { cursor: pointer; }

.resource-list-table tbody tr:hover {
  background-color: var(--pico-card-background-color);
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
  color: var(--pico-color);
  font-size: var(--fs-sm);
}

.resource-list-table .empty-value {
  color: var(--pico-muted-color);
}

.resource-list-table .instance-name {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
</style>
