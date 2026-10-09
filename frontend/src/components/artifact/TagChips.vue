<script setup>
import { computed } from 'vue'
import { searchParams } from '../../composables/useSearchScope.js'
import { symbolFor } from '../../composables/useAnnotationSymbols.js'

// The values of a tag annotation as chips. Each chip is a link to the search for that value; a machine tag
// (namespace:value) shows its namespace apart, and values with a known symbol carry it.
const props = defineProps({
  kind: { type: String, required: true },
  annotationKey: { type: String, required: true },
  values: { type: Array, required: true },
})

const MACHINE_TAG = /^([a-z][a-z0-9-]*):(.+)$/

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
    to: { name: 'search', query: searchParams(`${props.kind}: ${props.annotationKey} == "${quote(value)}"`) },
  }
}))
</script>

<template>
  <span class="chip-group">
    <router-link
      v-for="chip in chips"
      :key="chip.value"
      class="chip"
      :to="chip.to"
      :title="`Show ${kind} resources with ${annotationKey} = ${chip.value}`"
    >
      <i v-if="chip.symbol" :class="`iconoir-${chip.symbol} icon-application chip-symbol`" aria-hidden="true"></i>
      <span v-if="chip.namespace" class="chip-namespace">{{ chip.namespace }}</span>
      <span>{{ chip.label }}</span>
    </router-link>
  </span>
</template>
