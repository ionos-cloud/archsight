<script setup>
import { ref, watch, computed, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { getKindFilters } from '../../api/client.js'
import PageTree from '../page/PageTree.vue'
import { useSidebarTab } from '../../composables/useSidebarTab.js'
import { searchParams } from '../../composables/useSearchScope.js'

const props = defineProps({
  kinds: Object,
  pages: Array,
  pageFilters: { type: Array, default: () => [] }, // [{ key, title, values: [{ value, count }] }]
})

const route = useRoute()

const currentKind = computed(() => route.params.kind)
const filters = ref([])

// Pages and Kinds are tabs; the route picks the one that matches what is being viewed
// (see useSidebarTab), and search follows the tab
const { chosenTab, selectTab: chooseTab, TABS } = useSidebarTab()

const hasPages = computed(() => !!(props.pages && props.pages.length))
// without pages there is nothing to switch to
const activeTab = computed(() => (hasPages.value ? chosenTab.value : 'kinds'))

function selectTab(id, { focus = false } = {}) {
  chooseTab(id)
  if (focus) nextTick(() => document.getElementById(`sidebar-tab-${id}`)?.focus())
}

function onTabKeydown(event) {
  const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key]
  if (!step) return
  event.preventDefault()
  const index = TABS.findIndex((t) => t.id === activeTab.value)
  selectTab(TABS[(index + step + TABS.length) % TABS.length].id, { focus: true })
}

// kinds grouped by ArchiMate layer; "other" holds the tool's own kinds (pages, views, imports, ...)
const LAYERS = [
  { id: 'strategy', title: 'Strategy' },
  { id: 'motivation', title: 'Motivation' },
  { id: 'business', title: 'Business' },
  { id: 'application', title: 'Application' },
  { id: 'technology', title: 'Technology' },
  { id: 'other', title: 'Other' },
]

const kindGroups = computed(() => {
  const all = props.kinds?.kinds || []
  const known = new Set(LAYERS.map((l) => l.id))
  return LAYERS
    .map((layer) => ({
      ...layer,
      kinds: all.filter((k) => (known.has(k.layer) ? k.layer : 'other') === layer.id),
    }))
    .filter((group) => group.kinds.length)
})

// inside its layer group the layer prefix is redundant: BusinessActor under "Business" reads "Actor"
function kindLabel(kind, group) {
  const rest = group.id === 'other' ? '' : kind.slice(group.title.length)
  return kind.startsWith(group.title) && rest ? rest : kind
}

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

// page filters (status, tags, ...) search the pages: the search stays in the Pages scope (results link to the pages)
function pageFilterQuery(key, value) {
  return { name: 'search', query: searchParams(`Page: ${key} == "${value}"`, 'pages') }
}

function filterQuery(key, value) {
  const q = `${currentKind.value}: ${key} == "${value}"`
  return `/search?q=${encodeURIComponent(q)}`
}
</script>

<template>
  <aside class="sidebar">
    <div v-if="hasPages" class="sidebar-tabs" role="tablist" aria-label="Browse" @keydown="onTabKeydown">
      <button
        v-for="tab in TABS"
        :id="`sidebar-tab-${tab.id}`"
        :key="tab.id"
        type="button"
        role="tab"
        class="sidebar-tab"
        :aria-selected="activeTab === tab.id"
        :aria-controls="`sidebar-panel-${tab.id}`"
        :tabindex="activeTab === tab.id ? 0 : -1"
        @click="selectTab(tab.id)"
      >
        <i :class="tab.icon" aria-hidden="true"></i>
        <span>{{ tab.title }}</span>
      </button>
    </div>

    <div
      v-if="activeTab === 'pages'"
      id="sidebar-panel-pages"
      role="tabpanel"
      aria-labelledby="sidebar-tab-pages"
    >
      <div class="sidebar-section">
        <PageTree :nodes="pages" />
      </div>
      <div v-for="f in pageFilters" :key="f.key" class="sidebar-section">
        <div class="sidebar-label">
          <i :class="f.key === 'page/tags' ? 'iconoir-label' : 'iconoir-filter'" aria-hidden="true"></i> {{ f.title }}
        </div>
        <nav class="annotation-filter">
          <div class="filter-chips">
            <router-link v-for="v in f.values" :key="v.value" class="filter-chip" :to="pageFilterQuery(f.key, v.value)">
              {{ v.value }} <span class="kind-count">{{ v.count }}</span>
            </router-link>
          </div>
        </nav>
      </div>
    </div>

    <div
      v-else
      id="sidebar-panel-kinds"
      role="tabpanel"
      aria-labelledby="sidebar-tab-kinds"
    >
    <div class="sidebar-section">
      <nav class="kind-filter">
        <template v-if="kinds">
          <section v-for="group in kindGroups" :key="group.id" :class="['kind-group', `icon-${group.id}`]">
            <h3 class="kind-group-title">{{ group.title }}</h3>
            <ul>
              <li v-for="k in group.kinds" :key="k.kind">
                <router-link
                  :to="{ name: 'kind', params: { kind: k.kind } }"
                  :aria-current="isCurrentKind(k.kind) ? 'page' : undefined"
                >
                  <span class="kind-name" :title="k.kind">{{ kindLabel(k.kind, group) }}</span>
                  <span class="kind-count">{{ k.instance_count }}</span>
                </router-link>
              </li>
            </ul>
          </section>
        </template>
        <ul v-else>
          <li><span class="kind-name">Loading...</span></li>
        </ul>
      </nav>
    </div>
    <div v-if="filters.length" class="sidebar-section">
      <div class="sidebar-label"><i class="iconoir-filter" aria-hidden="true"></i> Filters</div>
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
  border-bottom: 1px solid var(--pico-muted-border-color);
}

/* Pages / Kinds tabs: compact, icon and label on one centre line */
.sidebar-tabs {
  display: flex;
  gap: 0.25rem;
  margin-bottom: 12px;
  border-bottom: 1px solid var(--pico-muted-border-color);
}

.sidebar-tab {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  width: auto;
  margin: 0 0 -1px;
  padding: 0.35rem 0.6rem;
  font-size: var(--fs-xs);
  font-weight: 600;
  line-height: 1;
  color: var(--pico-muted-color);
  background: transparent;
  border: none;
  border-bottom: 2px solid transparent;
  border-radius: 0;
  cursor: pointer;
}

.sidebar-tab i {
  flex-shrink: 0;
  font-size: var(--fs-md);
  line-height: 1;
}

.sidebar-tab:hover,
.sidebar-tab:focus-visible {
  color: var(--pico-color);
}

.sidebar-tab[aria-selected='true'] {
  color: var(--pico-primary);
  border-bottom-color: var(--pico-primary);
}

/* small label above Tags / Filters (they are not headings of their own any more) */
.sidebar-label {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin-bottom: 8px;
  font-size: var(--fs-2xs);
  font-weight: 600;
  line-height: 1;
  color: var(--pico-muted-color);
  text-transform: uppercase;
}

.sidebar-label i {
  flex-shrink: 0;
  font-size: var(--fs-md);
  line-height: 1;
}

.kind-group + .kind-group {
  margin-top: 0.75rem;
}

/* A group is a layer: its colour is a thin rail in the gutter left of the content edge (links already
   bleed 0.5rem into it), so the heading, the kind names and the tabs above share one left edge.
   The .icon-<layer> class on the section supplies the colour. */
.kind-group {
  position: relative;
}

.kind-group::before {
  content: '';
  position: absolute;
  top: 2px;
  bottom: 4px;
  left: -0.5rem;
  width: 3px;
  border-radius: 2px;
  background-color: currentColor;
}

/* Pico pulls every link up; for the first one that would let a selected row cover the group heading */
.kind-group li:first-child a {
  margin-top: 0;
}

.kind-group-title {
  margin: 0 0 2px;
  font-size: var(--fs-xs);
  font-weight: var(--fw-strong);
  line-height: var(--lh-heading);
  color: var(--pico-muted-color);
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
  font-size: var(--fs-xs);
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  text-decoration: none;
}

.kind-filter a[aria-current="page"],
.instance-list a[aria-current="page"] {
  background-color: var(--pico-primary);
  color: var(--pico-primary-inverse);
}

.kind-count {
  font-size: var(--fs-xs);
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
  font-size: var(--fs-2xs);
  font-weight: 600;
  color: var(--pico-muted-color);
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
  font-size: var(--fs-2xs);
  padding: 0.2rem 0.5rem;
  background-color: var(--pico-card-background-color);
  border: 1px solid var(--pico-muted-border-color);
  border-radius: 12px;
  text-decoration: none;
  color: var(--pico-color);
  transition: all 0.2s ease;
}

.filter-chip:hover {
  background-color: var(--pico-primary);
  color: var(--pico-primary-inverse);
  border-color: var(--pico-primary);
}

@media all and (min-width: 800px) {
  .sidebar {
    width: clamp(250px, 20vw, 400px);
    flex-shrink: 0;
  }
}
</style>
