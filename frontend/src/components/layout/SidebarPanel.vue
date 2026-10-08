<script setup>
import { ref, watch, computed, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { getKindFilters } from '../../api/client.js'
import PageTree from '../page/PageTree.vue'
import NavActions from './NavActions.vue'
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
    <div class="sidebar-head">
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
      <NavActions class="sidebar-actions" />
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
/* the Pages/Kinds row: tabs at the left, reload and help flush with the sidebar's right edge */
.sidebar-head {
  display: flex;
  align-items: center;
  margin-bottom: 12px;
  border-bottom: 1px solid var(--pico-muted-border-color);
}

.sidebar-tabs {
  display: flex;
  gap: 0.25rem;
}

.sidebar-actions {
  margin-left: auto;
  margin-bottom: 4px;
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

/* Pico redefines --pico-color on a hovered button (to the inverse, white), so use a variable it leaves alone */
.sidebar-tab:hover,
.sidebar-tab:focus-visible {
  color: var(--pico-contrast);
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

/* A group is a layer: a hairline in the layer colour sits under its heading. The .icon-<layer> class on the
   section supplies the colour; the rule is a pseudo-element so the heading text can stay muted
   (some layer colours are too light for text). */
.kind-group {
  display: flex;
  flex-direction: column;
}

.kind-group::before {
  content: '';
  order: 1;
  height: 1px;
  margin: 3px 0 6px; /* same width as the tab bar line and the Filters divider */
  background-color: var(--layer);
  opacity: 0.5; /* a quiet divider; the selected kind carries the full colour */
}

.kind-group > ul {
  order: 2;
}

/* Pico pulls every link up; for the first one that would let a selected row cover the group heading */
.kind-group li:first-child a {
  margin-top: 0;
}

.kind-group-title {
  margin: 0;
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

.instance-list a[aria-current="page"] {
  background-color: var(--pico-primary);
  color: var(--pico-primary-inverse);
}

/* the selected kind is outlined in its layer colour; an inset shadow keeps the text where it was.
   Pico redefines --pico-color and --pico-background-color on links, so use variables it leaves alone. */
.kind-filter a[aria-current="page"] {
  background-color: var(--pico-card-background-color);
  color: var(--pico-contrast);
  font-weight: var(--fw-strong);
  box-shadow: inset 0 0 0 2px var(--layer);
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

/* Sidebar above the content (below 800px, a phone): each group is a row of button-like tiles that wrap, the
   name on top and the count below, big enough for a thumb. A tile has a minimum width and grows to fit its
   name, so a long one ("ComplianceEvidence") widens its tile instead of wrapping. The group's hairline and
   heading stay. */
@media not all and (min-width: 800px) {
  .kind-group > ul {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem;
  }

  .kind-group li {
    flex: 0 1 auto;
    min-width: 7.5rem;
    max-width: 100%;
  }

  .kind-filter .kind-group a {
    flex-direction: column;
    align-items: flex-start;
    justify-content: space-between;
    gap: 0.25rem;
    min-height: 3.5rem;
    margin: 0;
    padding: 0.5rem 0.6rem;
    border-radius: var(--pico-border-radius);
    box-shadow: inset 0 0 0 1px var(--line);
  }

  .kind-filter .kind-group .kind-name {
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap; /* only the narrowest window truncates (the tooltip has the full name) */
  }

  .kind-filter .kind-group a[aria-current="page"] {
    box-shadow: inset 0 0 0 2px var(--layer);
  }

  .kind-filter .kind-group .kind-count {
    min-width: 0;
    padding: 0;
    text-align: left;
  }
}
</style>
