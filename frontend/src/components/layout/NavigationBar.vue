<script setup>
import { ref, inject, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { reload as apiReload } from '../../api/client.js'
import { useSearchScope, searchParams } from '../../composables/useSearchScope.js'

const router = useRouter()
const route = useRoute()
const { scope, placeholder } = useSearchScope()
const reloadKinds = inject('reloadKinds')
const query = ref('')
const searching = ref(false)
let debounceTimer = null

function onInput() {
  clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    if (query.value.trim()) {
      router.push({ name: 'search', query: searchParams(query.value, scope.value) })
    }
  }, 300)
}

function onSubmit() {
  clearTimeout(debounceTimer)
  if (query.value.trim()) {
    router.push({ name: 'search', query: searchParams(query.value, scope.value) })
  }
}

// Switching the sidebar tab while looking at results runs the same search in the other scope
watch(scope, (value) => {
  if (route.name === 'search' && route.query.q) {
    router.replace({ name: 'search', query: searchParams(route.query.q, value) })
  }
})

async function reload() {
  searching.value = true
  try {
    const result = await apiReload()
    if (result.error) {
      router.push({ name: 'error', query: { data: JSON.stringify(result.error) } })
    } else {
      await reloadKinds()
      window.location.reload()
    }
  } finally {
    searching.value = false
  }
}
</script>

<template>
  <nav class="container-fluid">
    <ul>
      <li>
        <strong>
          <router-link class="nav-link" to="/">
            <i class="iconoir-home"></i>
            Archsight
          </router-link>
        </strong>
      </li>
      <li>
        <a class="nav-link" href="#" @click.prevent="reload">
          <i class="iconoir-reload-window"></i>
          Reload
        </a>
      </li>
    </ul>
    <ul>
      <li class="search-container">
        <router-link class="search-help" to="/doc/index" title="Help">
          <i class="iconoir-help-circle"></i>
        </router-link>
        <input
          id="search-input"
          v-model="query"
          class="search"
          :placeholder="placeholder"
          @input="onInput"
          @keydown.enter.prevent="onSubmit"
        />
        <span v-if="searching" class="search-spinner">
          <i class="iconoir-refresh spinning"></i>
        </span>
      </li>
    </ul>
  </nav>
</template>

<style scoped>
/* icon and label share one centre line (an inline icon sits on the text baseline, a bit too high) */
.nav-link {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}

.nav-link i {
  flex-shrink: 0;
  line-height: 1;
}

.search-container {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.search-container input.search {
  min-width: 700px;
}

.spinning {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.search-help {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background-color: var(--card-background-color);
  border: 1px solid var(--muted-border-color);
  transition: all 0.2s ease;
  cursor: pointer;
  color: var(--muted-color);
}

.search-help:hover {
  background-color: var(--primary);
  color: var(--primary-inverse);
  border-color: var(--primary);
}

.search-help i {
  font-size: 1.1em;
}
</style>
