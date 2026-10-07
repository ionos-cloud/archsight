<script setup>
// A query the server could not parse. The message keeps the parser's caret under the failing spot.
defineProps({
  message: { type: String, required: true },
})
</script>

<template>
  <div class="query-error" role="alert">
    <div class="query-error-title"><i class="iconoir-warning-triangle" aria-hidden="true"></i> Query error</div>
    <pre class="query-error-message">{{ message }}</pre>
  </div>
</template>

<style scoped>
.query-error {
  margin-bottom: 0.75rem;
  padding: 0.5rem 0.75rem;
  border-left: 3px solid var(--pico-del-color);
  border-radius: 0 var(--pico-border-radius) var(--pico-border-radius) 0;
  background-color: color-mix(in srgb, var(--pico-del-color) 8%, transparent);
}

.query-error-title {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  color: var(--pico-del-color);
  font-size: var(--fs-xs);
  font-weight: var(--fw-strong);
}

.query-error-message {
  margin: 0.25rem 0 0;
  padding: 0;
  background: none;
  font-family: var(--font-mono);
  font-size: var(--fs-xs);
  white-space: pre-wrap;
  word-break: break-word;
}
</style>
