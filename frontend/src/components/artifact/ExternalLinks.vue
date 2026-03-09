<script setup>
import { computed } from 'vue'
import { iconForUrl, categoryForUrl } from '../../composables/useFormatting.js'

const props = defineProps({ annotations: Object })

const linkAnnotations = computed(() => {
  return Object.entries(props.annotations)
    .filter(([k]) => k.startsWith('link/'))
    .sort(([a], [b]) => a.localeCompare(b))
})

const hasLinks = computed(() => linkAnnotations.value.length > 0)

const groupedLinks = computed(() => {
  if (linkAnnotations.value.length <= 10) return null
  const groups = {}
  for (const [k, url] of linkAnnotations.value) {
    const cat = categoryForUrl(url)
    if (!groups[cat]) groups[cat] = []
    groups[cat].push({ key: k, url, name: k.replace('link/', '') })
  }
  return Object.entries(groups).sort(([a], [b]) => a.localeCompare(b))
})
</script>

<template>
  <tr v-if="hasLinks">
    <th scope="row">Links</th>
    <td>
      <template v-if="groupedLinks">
        <template v-for="[category, links] in groupedLinks" :key="category">
          <strong>{{ category }}</strong><br />
          <template v-for="link in links" :key="link.key">
            <a :href="link.url" target="_blank" rel="noopener noreferrer">
              <span :class="iconForUrl(link.url)"></span>
              {{ link.name }}
            </a><br />
          </template>
          <br />
        </template>
      </template>
      <template v-else>
        <template v-for="[k, url] in linkAnnotations" :key="k">
          <a :href="url" target="_blank" rel="noopener noreferrer">
            <span :class="iconForUrl(url)"></span>
            {{ k.replace('link/', '') }}
          </a><br />
        </template>
      </template>
    </td>
  </tr>
</template>
