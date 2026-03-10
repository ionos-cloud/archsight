<script setup>
import { computed } from 'vue'

const props = defineProps({
  field: Object,
  modelValue: [String, Number, null],
  error: [Array, null],
})

const emit = defineEmits(['update:modelValue', 'openMarkdown'])

const value = computed({
  get: () => props.modelValue ?? '',
  set: (v) => emit('update:modelValue', v),
})

const isFullWidth = computed(() =>
  ['textarea', 'markdown', 'code'].includes(props.field.input_type)
)

const hasError = computed(() => props.error && props.error.length > 0)
</script>

<template>
  <div class="field-group" :class="{ 'field-full-width': isFullWidth }">
    <div class="label-row">
      <label :for="field.key" :title="field.description">
        {{ field.title }}
        <span v-if="field.required" class="required">*</span>
      </label>
      <button
        v-if="field.input_type === 'markdown'"
        type="button"
        class="btn-edit-markdown"
        title="Open rich text editor"
        @click="$emit('openMarkdown', field.key)"
      >
        <i class="iconoir-edit-pencil"></i> Edit
      </button>
    </div>

    <!-- Select -->
    <select
      v-if="field.input_type === 'select'"
      :id="field.key"
      v-model="value"
      :aria-invalid="hasError ? 'true' : undefined"
    >
      <option value="">Select...</option>
      <option v-for="opt in field.options" :key="opt" :value="opt">{{ opt }}</option>
    </select>

    <!-- Textarea / Markdown -->
    <div v-else-if="field.input_type === 'textarea' || field.input_type === 'markdown'" class="markdown-field">
      <textarea
        :id="field.key"
        v-model="value"
        :aria-invalid="hasError ? 'true' : undefined"
        :placeholder="field.input_type === 'markdown' ? 'Enter markdown content...' : 'One entry per line...'"
      ></textarea>
      <small v-if="field.input_type === 'markdown'" class="future-hint">
        <i class="iconoir-info-circle"></i> Supports Markdown formatting
      </small>
    </div>

    <!-- Code -->
    <div v-else-if="field.input_type === 'code'" class="code-field">
      <textarea
        :id="field.key"
        v-model="value"
        :aria-invalid="hasError ? 'true' : undefined"
        :placeholder="`Enter ${field.code_language || ''} code...`"
        spellcheck="false"
      ></textarea>
      <small class="future-hint">
        <i class="iconoir-code"></i> {{ (field.code_language || '').charAt(0).toUpperCase() + (field.code_language || '').slice(1) }} code
      </small>
    </div>

    <!-- Number -->
    <input
      v-else-if="field.input_type === 'number'"
      :id="field.key"
      type="number"
      v-model="value"
      :step="field.step"
      :aria-invalid="hasError ? 'true' : undefined"
    />

    <!-- URL -->
    <input
      v-else-if="field.input_type === 'url'"
      :id="field.key"
      type="url"
      v-model="value"
      placeholder="https://..."
      :aria-invalid="hasError ? 'true' : undefined"
    />

    <!-- List -->
    <input
      v-else-if="field.input_type === 'list'"
      :id="field.key"
      type="text"
      v-model="value"
      placeholder="Comma-separated values"
      :aria-invalid="hasError ? 'true' : undefined"
    />

    <!-- Default text -->
    <input
      v-else
      :id="field.key"
      type="text"
      v-model="value"
      :aria-invalid="hasError ? 'true' : undefined"
    />

    <small
      v-if="field.description && !['textarea', 'markdown', 'code'].includes(field.input_type)"
      class="field-description"
    >{{ field.description }}</small>

    <div v-if="hasError" class="field-error">{{ error.join(', ') }}</div>
  </div>
</template>

<style scoped>
.field-group {
  margin-bottom: 0;
}

.field-group label {
  margin-bottom: 0.25rem;
}

.field-group label .required {
  color: var(--del-color);
  margin-left: 0.15rem;
}

.field-group input,
.field-group select,
.field-group textarea {
  margin-bottom: 0;
}

.field-description {
  font-size: 0.8rem;
  color: var(--muted-color);
  margin-top: 0.25rem;
}

.field-error {
  color: var(--del-color);
  font-size: 0.8rem;
  margin-top: 0.25rem;
}

.field-full-width {
  grid-column: 1 / -1;
}

.markdown-field textarea {
  font-family: var(--font-family-monospace);
  min-height: 200px;
  resize: vertical;
}

.code-field textarea {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
  font-size: 0.9em;
  line-height: 1.5;
  min-height: 600px;
  resize: vertical;
  tab-size: 2;
  white-space: pre;
  overflow-wrap: normal;
  overflow-x: auto;
}

.future-hint {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  color: var(--muted-color);
  font-size: 0.8rem;
  margin-top: 0.5rem;
}

.label-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 0.25rem;
}

.label-row label {
  margin-bottom: 0;
}

.btn-edit-markdown {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.25rem 0.5rem;
  font-size: 0.85rem;
  color: var(--muted-color);
  background: transparent;
  border: 1px solid var(--muted-border-color);
  border-radius: var(--border-radius);
  cursor: pointer;
  transition: all 0.15s ease;
}

.btn-edit-markdown:hover {
  color: var(--primary);
  border-color: var(--primary);
  background-color: transparent;
}

.btn-edit-markdown i {
  font-size: 0.9rem;
}

@media (prefers-color-scheme: dark) {
  .btn-edit-markdown {
    color: #8b949e;
    border-color: rgba(255, 255, 255, 0.15);
  }
  .btn-edit-markdown:hover {
    color: #58a6ff;
    border-color: #58a6ff;
  }
}
</style>
