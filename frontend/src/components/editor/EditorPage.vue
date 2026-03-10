<script setup>
import { ref, computed, onMounted, inject } from 'vue'
import { useRouter } from 'vue-router'
import { getEditorForm, getEditorEditForm, generateYaml, generateEditYaml } from '../../api/client.js'
import EditorField from './EditorField.vue'
import EditorRelations from './EditorRelations.vue'
import EditorYamlOutput from './EditorYamlOutput.vue'
import MarkdownEditor from './MarkdownEditor.vue'

const props = defineProps({
  kind: String,
  instance: String, // present in edit mode
})

const router = useRouter()
const kinds = inject('kinds')

const loading = ref(true)
const formMeta = ref(null)
const formError = ref(null)

const name = ref('')
const annotations = ref({})
const relations = ref([])
const errors = ref({})
const yamlOutput = ref(null)
const yamlPathRef = ref(null)
const yamlContentHash = ref(null)

const markdownFieldKey = ref(null)
const markdownVisible = ref(false)

const isEdit = computed(() => !!props.instance)
const title = computed(() => isEdit.value ? `Edit ${props.kind}` : `New ${props.kind}`)
const backUrl = computed(() =>
  isEdit.value
    ? `/kinds/${props.kind}/instances/${props.instance}`
    : `/kinds/${props.kind}`
)

const kindMeta = computed(() => {
  if (!kinds.value || !formMeta.value) return null
  return { icon: formMeta.value.icon, layer: formMeta.value.layer }
})

onMounted(async () => {
  try {
    const data = isEdit.value
      ? await getEditorEditForm(props.kind, props.instance)
      : await getEditorForm(props.kind)

    formMeta.value = data

    if (isEdit.value) {
      name.value = data.name || ''
      annotations.value = data.annotations || {}
      relations.value = data.relations || []
      yamlContentHash.value = data.content_hash
      yamlPathRef.value = data.path_ref
    }
  } catch (e) {
    formError.value = e.message
  } finally {
    loading.value = false
  }
})

async function submit() {
  errors.value = {}

  const payload = {
    name: name.value,
    annotations: annotations.value,
    relations: relations.value.map(r => ({
      verb: r.verb,
      kind: r.kind,
      names: [r.name],
    })),
    content_hash: yamlContentHash.value,
  }

  const result = isEdit.value
    ? await generateEditYaml(props.kind, props.instance, payload)
    : await generateYaml(props.kind, payload)

  if (result.errors) {
    errors.value = result.errors
  } else {
    yamlOutput.value = result.yaml
    if (result.path_ref) yamlPathRef.value = result.path_ref
    if (result.content_hash) yamlContentHash.value = result.content_hash
  }
}

function editAgain() {
  yamlOutput.value = null
}

function openMarkdown(key) {
  markdownFieldKey.value = key
  markdownVisible.value = true
}

function onMarkdownUpdate(val) {
  if (markdownFieldKey.value) {
    annotations.value[markdownFieldKey.value] = val
  }
}

function closeMarkdown() {
  markdownVisible.value = false
  markdownFieldKey.value = null
}
</script>

<template>
  <article v-if="loading"><p>Loading...</p></article>
  <article v-else-if="formError">
    <header><h2>Error</h2></header>
    <p>{{ formError }}</p>
  </article>

  <!-- YAML Output view -->
  <article v-else-if="yamlOutput" class="yaml-output">
    <header>
      <h3>
        <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
        {{ title }}
      </h3>
      <router-link class="btn-back" :to="backUrl">
        <i class="iconoir-arrow-left"></i> Back
      </router-link>
    </header>
    <EditorYamlOutput
      :yaml="yamlOutput"
      :kind="kind"
      :name="name"
      :content-hash="yamlContentHash"
      :path-ref="yamlPathRef"
      :inline-edit-enabled="formMeta.inline_edit_enabled"
      @edit-again="editAgain"
    />
  </article>

  <!-- Editor Form -->
  <template v-else-if="formMeta">
    <form class="editor-form" @submit.prevent="submit">
      <!-- Metadata -->
      <article>
        <header>
          <h3>
            <i v-if="kindMeta" :class="`iconoir-${kindMeta.icon} icon-${kindMeta.layer}`"></i>
            {{ title }}
          </h3>
          <router-link class="btn-back" :to="backUrl">
            <i class="iconoir-arrow-left"></i> Back
          </router-link>
        </header>

        <div v-if="isEdit" class="field-group">
          <input id="name" type="text" :value="name" disabled />
        </div>
        <div v-else class="field-group">
          <label for="name">
            Name <span class="required">*</span>
          </label>
          <input
            id="name"
            type="text"
            v-model="name"
            required
            placeholder="Enter resource name (no spaces)"
            pattern="\S+"
            :aria-invalid="errors.name ? 'true' : undefined"
          />
          <div v-if="errors.name" class="field-error">{{ errors.name.join(', ') }}</div>
        </div>
      </article>

      <!-- Annotations -->
      <article>
        <header><h3>Annotations</h3></header>
        <div class="annotations-grid">
          <EditorField
            v-for="field in formMeta.fields"
            :key="field.key"
            :field="field"
            :model-value="annotations[field.key]"
            :error="errors[field.key]"
            @update:model-value="v => annotations[field.key] = v"
            @open-markdown="openMarkdown"
          />
        </div>
      </article>

      <!-- Relations -->
      <article>
        <header><h3>Relations</h3></header>
        <EditorRelations
          :relations="relations"
          :relation-options="formMeta.relation_options"
          :instances-by-kind="formMeta.instances_by_kind"
          @update:relations="v => relations = v"
        />
      </article>

      <!-- Submit -->
      <div class="form-actions">
        <button type="submit">
          <i class="iconoir-code"></i> Generate YAML
        </button>
        <button type="button" class="secondary" @click="router.push(backUrl)">
          Cancel
        </button>
      </div>
    </form>

    <!-- Markdown Editor Overlay -->
    <MarkdownEditor
      :visible="markdownVisible"
      :model-value="markdownFieldKey ? (annotations[markdownFieldKey] || '') : ''"
      @update:model-value="onMarkdownUpdate"
      @close="closeMarkdown"
    />
  </template>
</template>

<style scoped>
.editor-form {
  max-width: 100%;
}

.annotations-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
}

.annotations-grid .field-full-width {
  grid-column: 1 / -1;
}

.form-actions {
  display: flex;
  gap: 0.75rem;
  margin-top: 1rem;
}

.form-actions button {
  width: auto;
  padding: 0.5rem 1.25rem;
  margin: 0;
}

.btn-back {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
  text-decoration: none;
}

/* Relations editor */
.relations-editor .relation-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.25rem 0;
}

.relations-editor .relation-text {
  flex: 1;
}

.relations-editor .btn-remove {
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.25rem;
  color: var(--pico-del-color, #c62828);
  margin: 0;
  width: auto;
}

.relations-editor .add-relation-row {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.5rem;
  align-items: flex-start;
}

.relations-editor .add-relation-row select {
  flex: 1;
  margin-bottom: 0;
}

.relations-editor .btn-add {
  white-space: nowrap;
  margin-bottom: 0;
}

.no-relations {
  color: var(--pico-muted-color);
  font-style: italic;
}

/* Field styles */
.field-group {
  margin-bottom: 0.5rem;
}

.field-group .label-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.25rem;
}

.field-group .required {
  color: var(--pico-del-color, #c62828);
}

.field-group .field-description {
  display: block;
  color: var(--pico-muted-color);
  margin-top: 0.125rem;
}

.field-group .field-error {
  color: var(--pico-del-color, #c62828);
  font-size: 0.875rem;
  margin-top: 0.125rem;
}

.field-group .btn-edit-markdown {
  background: none;
  border: 1px solid var(--pico-primary);
  color: var(--pico-primary);
  padding: 0.125rem 0.5rem;
  cursor: pointer;
  font-size: 0.75rem;
  border-radius: 4px;
  margin: 0;
  width: auto;
}

.field-group .future-hint {
  display: block;
  color: var(--pico-muted-color);
  margin-top: 0.125rem;
}

.field-group textarea {
  min-height: 8rem;
  font-family: inherit;
}

.field-group .code-field textarea {
  font-family: monospace;
}

/* YAML output */
.yaml-output-container .yaml-success {
  color: var(--pico-ins-color, #2e7d32);
}

.yaml-output-container pre {
  max-height: 60vh;
  overflow: auto;
}

.yaml-output-container .yaml-actions {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.5rem;
}

.yaml-output-container .yaml-file-info,
.yaml-output-container .yaml-instructions {
  color: var(--pico-muted-color);
}

.yaml-output-container .copied,
.yaml-output-container .saved {
  opacity: 0.8;
}

.conflict-error {
  background: var(--pico-del-color, #c62828);
  color: white;
  padding: 0.75rem 1rem;
  border-radius: 4px;
  margin-bottom: 1rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

/* Editor container */
.editor-container {
  width: 100%;
}

/* Editor header */
.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1.5rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--muted-border-color);
}

.editor-header h2 {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin: 0;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.btn-header {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.4rem 0.75rem;
  font-size: 0.9rem;
  color: var(--muted-color);
  background: transparent;
  border: 1px solid transparent;
  border-radius: var(--border-radius);
  text-decoration: none;
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-header:hover {
  color: var(--primary);
  border-color: var(--primary);
}

.yaml-output > header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.yaml-output > header h3 {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
}

@media (max-width: 768px) {
  .editor-header {
    flex-direction: column;
    align-items: flex-start;
    gap: 1rem;
  }
  .annotations-grid {
    grid-template-columns: 1fr;
  }
}
</style>
