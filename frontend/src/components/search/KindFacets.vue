<script setup>
import { computed, inject } from 'vue'
import { useRoute } from 'vue-router'

// How many hits each kind has (by_kind of the search response); a chip narrows the search to that kind.
// The selected chip is outlined in its layer colour, like the selected kind in the sidebar.
const props = defineProps({
  byKind: { type: Object, default: () => ({}) },
  selected: { type: String, default: null },
})

const LAYERS = ['strategy', 'motivation', 'business', 'application', 'technology', 'other']

const route = useRoute()
const kinds = inject('kinds', null)

const layerOf = computed(() => Object.fromEntries((kinds?.value?.kinds || []).map((k) => [k.kind, k.layer])))

const chips = computed(() =>
  Object.entries(props.byKind)
    .map(([kind, count]) => ({ kind, count, layer: LAYERS.includes(layerOf.value[kind]) ? layerOf.value[kind] : 'other' }))
    .sort((a, b) => LAYERS.indexOf(a.layer) - LAYERS.indexOf(b.layer) || a.kind.localeCompare(b.kind)),
)
const total = computed(() => chips.value.reduce((sum, chip) => sum + chip.count, 0))

function to(kind) {
  const query = { ...route.query }
  if (kind) query.kind = kind
  else delete query.kind
  return { name: 'search', query }
}
</script>

<template>
  <nav class="kind-facets" aria-label="Filter by kind">
    <router-link
      class="facet facet-all"
      :class="{ selected: !selected }"
      :to="to(null)"
      :aria-current="!selected ? 'true' : undefined"
    >
      All <span class="facet-count">{{ total }}</span>
    </router-link>
    <router-link
      v-for="chip in chips"
      :key="chip.kind"
      class="facet"
      :class="[`icon-${chip.layer}`, { selected: selected === chip.kind }]"
      :to="to(chip.kind)"
      :aria-current="selected === chip.kind ? 'true' : undefined"
    >
      <span class="facet-dot" aria-hidden="true"></span>
      {{ chip.kind }} <span class="facet-count">{{ chip.count }}</span>
    </router-link>
  </nav>
</template>

<style scoped>
.kind-facets {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-start; /* Pico spreads the items of a nav */
  gap: 0.35rem;
  margin-bottom: 0.75rem;
}

/* --layer comes from the .icon-<layer> class (base.css) */
.facet {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  margin: 0;
  padding: 0.2rem 0.6rem;
  border-radius: var(--pico-border-radius);
  background-color: transparent;
  box-shadow: inset 0 0 0 1px var(--line);
  color: var(--pico-color);
  font-size: var(--fs-xs);
  text-decoration: none;
  transition: background-color 0.15s ease;
}

.facet:hover {
  background-color: var(--tint);
}

.facet-all {
  --layer: var(--pico-primary);
}

.facet.selected {
  background-color: var(--pico-card-background-color);
  box-shadow: inset 0 0 0 2px var(--layer); /* no bolder text: a wider chip would nudge its neighbours */
}

.facet-dot {
  width: 0.5rem;
  height: 0.5rem;
  border-radius: 2px;
  background-color: var(--layer);
}

.facet-count {
  color: var(--pico-muted-color);
  font-weight: normal;
  font-variant-numeric: tabular-nums;
}
</style>
