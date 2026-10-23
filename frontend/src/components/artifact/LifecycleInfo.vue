<script setup>
import { computed } from 'vue'
import { keyHint } from '../../composables/useKeyHint.js'
import TagChips from './TagChips.vue'

// The lifecycle of a resource on one line: its status as a chip, behind it the resource that replaces it (a link, plain
// text when it does not resolve) and, for a resource that is going away, how many resources still refer to it (a link
// to the Incoming relations).
const props = defineProps({
  annotations: Object,
  kind: String,
  links: { type: Object, default: () => ({}) },
  incoming: { type: Number, default: 0 },
})

const RETIRING = ['deprecated', 'sunset', 'end-of-life']

const status = computed(() => props.annotations['lifecycle/status'])
const replacedBy = computed(() => props.annotations['lifecycle/replacedBy'])
const replacementLink = computed(() => props.links?.['lifecycle/replacedBy'] || null)
const stillReferenced = computed(() => RETIRING.includes(status.value) && props.incoming > 0)
</script>

<template>
  <tr v-if="status || replacedBy">
    <th scope="row" :title="keyHint('lifecycle/status')">Lifecycle</th>
    <td>
      <div class="lifecycle-info">
        <TagChips v-if="status" :kind="kind" annotation-key="lifecycle/status" :values="[status]" />
        <span v-if="replacedBy" class="lifecycle-replaced" :title="keyHint('lifecycle/replacedBy')">
          <i class="iconoir-arrow-right" aria-hidden="true"></i>
          replaced by
          <router-link v-if="replacementLink" :to="replacementLink">{{ replacedBy }}</router-link>
          <template v-else>{{ replacedBy }}</template>
        </span>
        <router-link v-if="stillReferenced" class="lifecycle-incoming" :to="{ hash: '#incoming' }">
          {{ incoming }} incoming
        </router-link>
      </div>
    </td>
  </tr>
</template>

<style scoped>
.lifecycle-info {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.25rem 0.75rem;
}

.lifecycle-replaced,
.lifecycle-incoming {
  font-size: var(--fs-sm);
  color: var(--pico-muted-color);
}

.lifecycle-replaced a {
  font-weight: 600;
}
</style>
