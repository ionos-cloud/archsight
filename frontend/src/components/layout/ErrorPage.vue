<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { reload as apiReload } from '../../api/client.js'

const route = useRoute()
const router = useRouter()

const error = computed(() => {
  try {
    return route.query.data ? JSON.parse(route.query.data) : null
  } catch {
    return null
  }
})

async function retry() {
  const result = await apiReload()
  if (result.error) {
    router.replace({ name: 'error', query: { data: JSON.stringify(result.error) } })
  } else {
    router.push('/')
    window.location.reload()
  }
}
</script>

<template>
  <div v-if="error">
    <header>
      <article class="error-header">
        <h3>
          <i class="iconoir-warning-triangle"></i>
          Error
        </h3>
        <p class="error-message">{{ error.error }}</p>
        <p class="error-location">
          <i class="iconoir-page"></i>
          {{ error.path }}
          <span class="error-line-badge">Line {{ error.line_no }}</span>
        </p>
      </article>
      <a href="#" class="reload-btn" @click.prevent="retry">
        <i class="iconoir-refresh"></i>
        Reload
      </a>
    </header>

    <div class="error-code-block" v-if="error.context">
      <pre><code><span
        v-for="line in error.context"
        :key="line.line_no"
        :class="line.selected ? 'error-line' : 'code-line'"
      ><span class="line-number">{{ String(line.line_no).padStart(4, ' ') }}</span>{{ line.content }}
</span></code></pre>
    </div>
  </div>
  <div v-else>
    <p>No error data available.</p>
    <router-link to="/">Back to home</router-link>
  </div>
</template>

<style scoped>
.error-header {
  margin-bottom: 1rem;
}

.error-header h3 {
  color: #dc2626;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}

.error-message {
  font-size: 1.1rem;
  margin-bottom: 0.5rem;
}

.error-location {
  color: #6b7280;
  font-family: monospace;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.error-line-badge {
  background-color: #dc2626;
  color: white;
  padding: 0.125rem 0.5rem;
  border-radius: 4px;
  font-size: 0.875rem;
}

.reload-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.25rem;
}

.error-code-block {
  width: 100%;
  overflow-x: auto;
}

.error-code-block pre {
  margin: 0;
  padding: 1rem;
  background-color: #1e1e1e;
  border-radius: 8px;
  overflow-x: auto;
}

.error-code-block code {
  font-family: 'SF Mono', 'Monaco', 'Menlo', 'Consolas', monospace;
  font-size: 0.8rem;
  line-height: 1.1;
}

.error-code-block .code-line,
.error-code-block .error-line {
  display: block;
  white-space: pre;
}

.error-code-block .code-line {
  color: #d4d4d4;
}

.error-code-block .error-line {
  background-color: rgba(220, 38, 38, 0.3);
  color: #fca5a5;
  margin: 0 -1rem;
  padding: 0 1rem;
}

.error-code-block .line-number {
  color: #6b7280;
  user-select: none;
  margin-right: 1rem;
  display: inline-block;
  min-width: 3rem;
  text-align: right;
}

.error-code-block .error-line .line-number {
  color: #f87171;
}

@media (prefers-color-scheme: dark) {
  .error-header h3 {
    color: #f87171;
  }
  .error-location {
    color: #9ca3af;
  }
}
</style>
