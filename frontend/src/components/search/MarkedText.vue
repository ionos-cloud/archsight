<script setup>
import { computed } from 'vue'

// Text with ranges to highlight ([[from, to], ...], as the search API sends them), as text nodes and <mark>s:
// nothing is parsed as HTML
const props = defineProps({
  text: { type: String, required: true },
  marks: { type: Array, default: () => [] },
})

// the offsets count characters (code points), so the text is sliced by code points, not UTF-16 units
const parts = computed(() => {
  const chars = Array.from(props.text)
  const slice = (from, to) => chars.slice(from, to).join('')
  const out = []
  let at = 0
  for (const [from, to] of props.marks) {
    if (from < at || to <= from) continue
    if (from > at) out.push({ text: slice(at, from), mark: false })
    out.push({ text: slice(from, to), mark: true })
    at = to
  }
  if (at < chars.length) out.push({ text: slice(at), mark: false })
  return out
})
</script>

<template><template v-for="(part, i) in parts" :key="i"><mark v-if="part.mark" class="search-mark">{{ part.text }}</mark><template v-else>{{ part.text }}</template></template></template>

<style scoped>
.search-mark {
  padding: 0 1px;
  border-radius: 2px;
  background-color: var(--pico-mark-background-color);
  color: var(--pico-mark-color);
  font-weight: 600;
}
</style>
