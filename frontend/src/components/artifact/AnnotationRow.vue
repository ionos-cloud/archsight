<script setup>
import { keyHint } from '../../composables/useKeyHint.js'
import { ref, computed } from 'vue'
import { useInternalLinks } from '../../composables/useInternalLinks.js'
import { labelFor, displayValue } from '../../composables/useAnnotationSymbols.js'
import TagChips from './TagChips.vue'

const props = defineProps({
  annotationKey: String,
  value: [String, Number, Boolean],
  kind: String,
  format: { type: String, default: null },
})

const mdEl = ref(null)
useInternalLinks(mdEl)

const label = computed(() => {
  const override = labelFor(props.annotationKey)
  if (override) return override
  const parts = props.annotationKey.split('/')
  return parts[parts.length - 1].replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase())
})

const isUrl = computed(() => {
  return typeof props.value === 'string' && /^https?:\/\//.test(props.value)
})

// an identifier (alias) points at one resource, so it is plain text: never a chip, never a link
const identifiers = computed(() => {
  if (props.format !== 'identifier' || props.value == null) return []
  return String(props.value).split(',').map(s => s.trim()).filter(Boolean)
})

// the values of a tag annotation: a list is comma separated, a word is a single value
const tagValues = computed(() => {
  if (!['tag_list', 'tag_word'].includes(props.format) || props.value == null) return []
  const text = String(props.value)
  return props.format === 'tag_list' ? text.split(',').map(s => s.trim()).filter(Boolean) : [text]
})
</script>

<template>
  <tr>
    <th scope="row" :title="keyHint(annotationKey)">{{ label }}</th>
    <td>
      <template v-if="format === 'markdown'">
        <div ref="mdEl" v-html="value"></div>
      </template>
      <template v-else-if="identifiers.length">{{ identifiers.join(', ') }}</template>
      <TagChips v-else-if="tagValues.length" :kind="kind" :annotation-key="annotationKey" :values="tagValues" />
      <template v-else>
        <a v-if="isUrl" :href="value" target="_blank">{{ value }}</a>
        <template v-else>{{ displayValue(annotationKey, value) }}</template>
      </template>
    </td>
  </tr>
</template>
