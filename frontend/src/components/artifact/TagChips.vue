<script setup>
import { computed } from 'vue'
import { searchParams } from '../../composables/useSearchScope.js'
import { symbolFor } from '../../composables/useAnnotationSymbols.js'

// The values of a tag annotation as chips. Each chip is a link to the search for that value; a machine tag
// (namespace:value) or a namespaced alias (ITGS:A001) shows its namespace apart, and values with a known symbol carry
// it. Unlinked chips (aliases) show the values only: an alias points at the one resource that is already open.
const props = defineProps({
  kind: { type: String, required: true },
  annotationKey: { type: String, required: true },
  values: { type: Array, required: true },
  linked: { type: Boolean, default: true },
})

// lifecycle states that call for attention get a tone: deprecated warns, sunset and end-of-life are over
const LIFECYCLE_TONES = { deprecated: 'chip-warning', sunset: 'chip-danger', 'end-of-life': 'chip-danger' }

const MACHINE_TAG = /^([a-z][a-z0-9-]*):(.+)$/i

function quote(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')
}

const chips = computed(() => props.values.map((value) => {
  const machine = MACHINE_TAG.exec(value)
  return {
    value,
    namespace: machine ? machine[1] : null,
    label: machine ? machine[2] : value,
    symbol: symbolFor(props.annotationKey, value),
    tone: props.annotationKey === 'lifecycle/status' ? LIFECYCLE_TONES[value] || null : null,
    to: { name: 'search', query: searchParams(`${props.kind}: ${props.annotationKey} == "${quote(value)}"`) },
  }
}))
</script>

<template>
  <span class="chip-group">
    <component
      :is="linked ? 'router-link' : 'span'"
      v-for="chip in chips"
      :key="chip.value"
      class="chip"
      :class="chip.tone"
      :to="linked ? chip.to : undefined"
      :title="linked ? `Show ${kind} resources with ${annotationKey} = ${chip.value}` : undefined"
    >
      <i v-if="chip.symbol" :class="`iconoir-${chip.symbol} icon-application chip-symbol`" aria-hidden="true"></i>
      <span v-if="chip.namespace" class="chip-namespace">{{ chip.namespace }}</span>
      <span>{{ chip.label }}</span>
    </component>
  </span>
</template>
