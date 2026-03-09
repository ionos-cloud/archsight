<script setup>
import { computed, inject } from 'vue'

const props = defineProps({
  data: Object,
})

const kinds = inject('kinds')

const relations = computed(() => props.data.relations || {})
const references = computed(() => props.data.references || {})
const hasAny = computed(() => Object.keys(relations.value).length > 0 || Object.keys(references.value).length > 0)

function kindMeta(kindName) {
  if (!kinds?.value?.kinds) return null
  return kinds.value.kinds.find(k => k.kind === kindName)
}

function kindIcon(kindName) {
  const meta = kindMeta(kindName)
  return meta?.icon || 'cube'
}

function kindLayer(kindName) {
  const meta = kindMeta(kindName)
  return meta?.layer || 'technology'
}

// Flatten relations: { verb: { kind: [names] } } -> grouped list
const outgoing = computed(() => {
  const groups = []
  for (const [verb, kinds] of Object.entries(relations.value)) {
    for (const [kind, names] of Object.entries(kinds)) {
      groups.push({ verb, kind, names: [...names].sort() })
    }
  }
  return groups
})

// Flatten references: { kind: { verb: [names] } } -> grouped list
const incoming = computed(() => {
  const groups = []
  for (const [kind, verbs] of Object.entries(references.value)) {
    for (const [verb, names] of Object.entries(verbs)) {
      groups.push({ verb: verb || 'references', kind, names: [...names].sort() })
    }
  }
  return groups
})
</script>

<template>
  <article v-if="hasAny" class="relations-section">
    <header><h2>Relations</h2></header>
    <div class="relations-grid">
      <div class="relations-column relations-outgoing">
        <h3>Outgoing <i class="iconoir-arrow-right"></i></h3>
        <template v-if="outgoing.length">
          <div v-for="(group, i) in outgoing" :key="'out-' + i" class="relation-group">
            <div class="relation-kind">
              <i :class="`iconoir-${kindIcon(group.kind)} icon-${kindLayer(group.kind)}`"></i>
              <span>{{ group.kind }} ({{ group.names.length }})</span>
            </div>
            <div class="relation-verb">{{ group.verb }} ({{ group.names.length }})</div>
            <div class="instance-badges">
              <router-link
                v-for="name in group.names"
                :key="name"
                class="badge badge-info"
                :to="{ name: 'instance', params: { kind: group.kind, instance: name } }"
              >
                {{ name }}
              </router-link>
            </div>
          </div>
        </template>
        <div v-else class="relations-empty">None</div>
      </div>

      <div class="relations-column relations-incoming">
        <h3><i class="iconoir-arrow-right"></i> Incoming</h3>
        <template v-if="incoming.length">
          <div v-for="(group, i) in incoming" :key="'in-' + i" class="relation-group">
            <div class="relation-kind">
              <i :class="`iconoir-${kindIcon(group.kind)} icon-${kindLayer(group.kind)}`"></i>
              <span>{{ group.kind }} ({{ group.names.length }})</span>
            </div>
            <div class="relation-verb">{{ group.verb }} ({{ group.names.length }})</div>
            <div class="instance-badges">
              <router-link
                v-for="name in group.names"
                :key="name"
                class="badge badge-info"
                :to="{ name: 'instance', params: { kind: group.kind, instance: name } }"
              >
                {{ name }}
              </router-link>
            </div>
          </div>
        </template>
        <div v-else class="relations-empty">None</div>
      </div>
    </div>
  </article>
</template>

<style scoped>
.relations-section .relations-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1.5rem;
}

.relations-section .relations-outgoing {
  order: 2;
}

.relations-section .relations-incoming {
  order: 1;
}

@media (max-width: 768px) {
  .relations-section .relations-grid {
    grid-template-columns: 1fr;
    gap: 1rem;
  }
  .relations-section .relations-outgoing {
    order: 1;
  }
  .relations-section .relations-incoming {
    order: 2;
  }
}

.relations-section .relations-column h3 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
  color: var(--muted-color);
  font-size: 1rem;
  font-weight: 600;
}

.relations-section .relation-group {
  margin-bottom: 0.75rem;
  padding: 0.5rem 0.75rem;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 0.5rem;
}

.relations-section .relation-kind {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-weight: 600;
  margin-bottom: 0.25rem;
}

.relations-section .relation-verb {
  font-size: 0.875rem;
  color: var(--muted-color);
  margin-bottom: 0.5rem;
}

.relations-section .relations-empty {
  color: var(--muted-color);
  font-style: italic;
}

.instance-badges {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
</style>
