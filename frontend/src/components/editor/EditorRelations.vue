<script setup>
import { ref, computed, watch } from 'vue'

const props = defineProps({
  relations: Array,
  relationOptions: Array,
  instancesByKind: Object,
})

const emit = defineEmits(['update:relations'])

const selectedCombo = ref('')
const selectedInstance = ref('')

const sortedRelations = computed(() => {
  return [...props.relations].sort((a, b) => {
    return (a.verb + a.kind + a.name).localeCompare(b.verb + b.kind + b.name)
  })
})

const selectedTargetKind = computed(() => {
  if (!selectedCombo.value) return null
  const opt = props.relationOptions.find(r => r.combo === selectedCombo.value)
  return opt?.target_kind
})

const instanceOptions = computed(() => {
  if (!selectedTargetKind.value) return []
  return props.instancesByKind[selectedTargetKind.value] || []
})

watch(selectedCombo, () => {
  selectedInstance.value = ''
})

function addRelation() {
  if (!selectedCombo.value || !selectedInstance.value) return

  const opt = props.relationOptions.find(r => r.combo === selectedCombo.value)
  if (!opt) return

  // Check for duplicate
  const exists = props.relations.some(
    r => r.verb === opt.verb && r.kind === opt.target_kind && r.name === selectedInstance.value
  )
  if (exists) return

  const updated = [...props.relations, {
    verb: opt.verb,
    kind: opt.target_kind,
    name: selectedInstance.value,
  }]
  emit('update:relations', updated)

  selectedCombo.value = ''
  selectedInstance.value = ''
}

function removeRelation(index) {
  const updated = props.relations.filter((_, i) => i !== index)
  emit('update:relations', updated)
}
</script>

<template>
  <div class="relations-editor">
    <p v-if="!relationOptions || relationOptions.length === 0" class="no-relations">
      This resource type has no defined relations.
    </p>
    <template v-else>
      <!-- Existing relations -->
      <div id="relations-list">
        <div v-for="(rel, idx) in sortedRelations" :key="`${rel.verb}:${rel.kind}:${rel.name}`" class="relation-item">
          <span class="relation-text">
            <strong>{{ rel.verb }}</strong> &rarr; {{ rel.kind }}: <em>{{ rel.name }}</em>
          </span>
          <button class="btn-remove" type="button" title="Remove" @click="removeRelation(idx)">
            <i class="iconoir-xmark"></i>
          </button>
        </div>
      </div>

      <!-- Add relation -->
      <div class="add-relation-row">
        <select v-model="selectedCombo">
          <option value="">Select relation...</option>
          <option v-for="opt in relationOptions" :key="opt.combo" :value="opt.combo">
            {{ opt.verb }} &rarr; {{ opt.target_kind }}
          </option>
        </select>

        <select v-model="selectedInstance">
          <option value="">Select instance...</option>
          <option v-for="inst in instanceOptions" :key="inst" :value="inst">{{ inst }}</option>
        </select>

        <button class="secondary btn-add" type="button" @click="addRelation">
          <i class="iconoir-plus"></i> Add
        </button>
      </div>
    </template>
  </div>
</template>

<style scoped>
.relations-editor {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

#relations-list {
  display: flex;
  flex-direction: column;
  background-color: var(--background-color);
  border: 1px solid var(--muted-border-color);
  border-radius: 4px;
}

#relations-list:empty {
  display: none;
}

.relation-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  padding: 0.35rem 0.5rem;
  font-size: 0.9rem;
  border-bottom: 1px solid var(--muted-border-color);
}

.relation-item:last-child {
  border-bottom: none;
}

.relation-text {
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.relation-text strong {
  font-weight: 600;
}

.relation-text em {
  font-style: normal;
  color: var(--muted-color);
}

.btn-remove {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  padding: 0;
  margin: 0;
  background: transparent;
  border: none;
  border-radius: 3px;
  color: var(--muted-color);
  cursor: pointer;
  flex-shrink: 0;
}

.btn-remove:hover {
  background-color: var(--del-color);
  color: white;
}

.btn-remove i {
  font-size: 0.85rem;
}

.add-relation-row {
  display: flex;
  gap: 0.5rem;
  align-items: center;
}

.add-relation-row select {
  margin: 0;
  flex: 1;
}

.add-relation-row select:first-child {
  flex: 1.2;
}

.btn-add {
  margin: 0;
  white-space: nowrap;
  flex-shrink: 0;
}

.no-relations {
  color: var(--muted-color);
  font-style: italic;
  margin: 0;
}

@media (max-width: 768px) {
  .add-relation-row {
    flex-direction: column;
  }
  .add-relation-row select,
  .add-relation-row button {
    width: 100%;
  }
}
</style>
