<script setup>
import HighlightValue from './HighlightValue.vue'

// The summary attributes of one hit, in the order the kind defines them
defineProps({
  items: { type: Array, required: true },
  kind: { type: String, required: true },
})
</script>

<template>
  <div class="highlights">
    <HighlightValue v-for="item in items" :key="item.key" :item="item" :kind="kind" />
  </div>
</template>

<style scoped>
.highlights {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 0.25rem 0.9rem;
  max-width: 60%;
}
</style>
