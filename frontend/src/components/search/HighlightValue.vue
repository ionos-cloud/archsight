<script setup>
import { computed } from 'vue'
import { timeAgo } from '../../composables/useFormatting.js'
import { searchParams } from '../../composables/useSearchScope.js'
import { keyHint } from '../../composables/useKeyHint.js'

// One summary attribute of a search hit ({ key, title, value, format, type }, see the search API).
// How it is shown follows its shape: tags refine the query, numbers and times are plain, people lose the e-mail.
const props = defineProps({
  item: { type: Object, required: true },
  kind: { type: String, required: true },
})

const MAX_TAGS = 2

const isTime = computed(() => props.item.type === 'Time')
const isNumber = computed(() => typeof props.item.value === 'number')
const isPerson = computed(() => ['Person', 'EmailRecipient'].includes(props.item.type))
const isTag = computed(() => ['tag_word', 'tag_list'].includes(props.item.format))

const values = computed(() => (Array.isArray(props.item.value) ? props.item.value : [props.item.value]))
const shownTags = computed(() => values.value.slice(0, MAX_TAGS))
const hiddenTags = computed(() => values.value.length - shownTags.value.length)

const tooltip = computed(() =>
  keyHint(props.item.title, props.item.key, isTime.value ? props.item.value : null),
)

// "Name <mail>" shows as "Name"
const personName = computed(() => String(props.item.value).replace(/\s*<[^>]*>/, '').trim() || String(props.item.value))

function refine(value) {
  const q = `${props.kind}: ${props.item.key} == "${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
  return { name: 'search', query: searchParams(q, props.kind === 'Page' ? 'pages' : 'kinds') }
}
</script>

<template>
  <span class="hl" :title="tooltip">
    <template v-if="isNumber">
      <span class="hl-label">{{ item.title }}</span>
      <span class="hl-number">{{ item.value.toLocaleString('en') }}</span>
    </template>
    <template v-else-if="isTime">{{ timeAgo(item.value) }}</template>
    <template v-else-if="isPerson">{{ personName }}</template>
    <template v-else-if="isTag">
      <router-link v-for="value in shownTags" :key="value" class="hl-tag" :to="refine(value)">{{ value }}</router-link>
      <span v-if="hiddenTags > 0" class="hl-more">+{{ hiddenTags }}</span>
    </template>
    <template v-else>{{ values.join(', ') }}</template>
  </span>
</template>

<style scoped>
.hl {
  display: inline-flex;
  align-items: baseline;
  gap: 0.3rem;
  max-width: 16rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: var(--fs-xs);
  color: var(--pico-muted-color);
}

.hl-label {
  max-width: 9rem;
  overflow: hidden;
  text-overflow: ellipsis;
  font-size: var(--fs-2xs);
}

.hl-number {
  font-variant-numeric: tabular-nums;
  color: var(--pico-color);
}

/* above the row's stretched link, so a tag stays clickable */
.hl-tag {
  position: relative;
  z-index: 1;
  padding: 1px 8px;
  border-radius: 10px;
  background-color: var(--tint);
  color: var(--pico-color);
  text-decoration: none;
  transition: background-color 0.15s ease, color 0.15s ease;
}

.hl-tag:hover,
.hl-tag:focus-visible {
  background-color: color-mix(in srgb, var(--pico-primary) 14%, transparent);
  color: var(--pico-primary);
}

.hl-more {
  font-size: var(--fs-2xs);
}
</style>
