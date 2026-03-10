<script setup>
import { ref, computed } from 'vue'
import { useInternalLinks } from '../../composables/useInternalLinks.js'

const props = defineProps({
  annotationKey: String,
  value: [String, Number, Boolean],
  kind: String,
  format: { type: String, default: null },
})

const mdEl = ref(null)
useInternalLinks(mdEl)

const label = computed(() => {
  const parts = props.annotationKey.split('/')
  return parts[parts.length - 1].replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, c => c.toUpperCase())
})

const isUrl = computed(() => {
  return typeof props.value === 'string' && /^https?:\/\//.test(props.value)
})

const tags = computed(() => {
  if (props.format !== 'tag_list' || typeof props.value !== 'string') return []
  return props.value.split(',').map(s => s.trim()).filter(Boolean)
})

function filterQuery(val) {
  return `/search?q=${encodeURIComponent(`${props.kind}: ${props.annotationKey} == "${val}"`)}`
}
</script>

<template>
  <tr>
    <th scope="row">{{ label }}</th>
    <td>
      <template v-if="format === 'markdown'">
        <div ref="mdEl" v-html="value"></div>
      </template>
      <template v-else-if="format === 'tag_list'">
        <div class="instance-badges">
          <router-link
            v-for="tag in tags"
            :key="tag"
            class="badge badge-info"
            :to="filterQuery(tag)"
          >
            {{ tag }}
          </router-link>
        </div>
      </template>
      <template v-else-if="format === 'tag_word'">
        <router-link class="badge badge-info" :to="filterQuery(value)">
          {{ value }}
        </router-link>
      </template>
      <template v-else>
        <a v-if="isUrl" :href="value" target="_blank">{{ value }}</a>
        <template v-else>{{ value }}</template>
      </template>
    </td>
  </tr>
</template>
