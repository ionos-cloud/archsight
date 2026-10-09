<script setup>
import { computed } from 'vue'
import { iconForUrl } from '../../composables/useFormatting.js'
import { linkLabel, linkHost, sortedLinks, groupedLinks, GROUP_FROM } from '../../composables/useLinks.js'

// The links of a resource or page ({ name: url }): each is a chip with the icon of its system, its name and the
// host it points to. Resources with many links (the ones found in a README) are listed by category instead.
const props = defineProps({ links: { type: Object, default: () => ({}) } })

const entries = computed(() => sortedLinks(props.links))
const grouped = computed(() => (entries.value.length > GROUP_FROM ? groupedLinks(entries.value) : null))
</script>

<template>
  <div v-if="grouped" class="link-groups">
    <section v-for="[category, links] in grouped" :key="category">
      <strong>{{ category }}</strong>
      <ul>
        <li v-for="link in links" :key="link.name">
          <a :href="link.url" target="_blank" rel="noopener noreferrer" :title="link.url">
            <i :class="iconForUrl(link.url)" aria-hidden="true"></i> {{ link.name }}
          </a>
        </li>
      </ul>
    </section>
  </div>
  <span v-else-if="entries.length" class="chip-group">
    <a
      v-for="[name, url] in entries"
      :key="name"
      class="chip link-chip"
      :href="url"
      target="_blank"
      rel="noopener noreferrer"
      :title="`Open ${url}`"
    >
      <i :class="`${iconForUrl(url)} link-icon`" aria-hidden="true"></i>
      <span>{{ linkLabel(name) }}</span>
      <span v-if="linkHost(url)" class="link-host">{{ linkHost(url) }}</span>
    </a>
  </span>
</template>

<style scoped>
.link-groups section + section {
  margin-top: var(--space-2);
}

.link-groups ul {
  margin: 0;
  padding: 0;
  list-style: none;
}
</style>
