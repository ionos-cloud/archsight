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
      <li class="nav-actions-item">
        <!-- one segmented control: reload and help -->
        <div class="nav-actions" role="group" aria-label="Actions">
          <a class="nav-action" href="#" title="Reload" aria-label="Reload" @click.prevent="reload">
            <i class="iconoir-reload-window" aria-hidden="true"></i>
          </a>
          <router-link class="nav-action" to="/doc/index" title="Help" aria-label="Help">
            <i class="iconoir-help-circle" aria-hidden="true"></i>
          </router-link>
        </div>
      </li>
    </ul>
    <ul>
      <li class="search-container">
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

/* reload and help as one segmented control: icon-only, a shared hairline between the two */
.nav-actions-item {
  display: flex;
  align-items: center;
}

.nav-actions {
  display: inline-flex;
  margin: 0; /* Pico's [role="group"] adds a bottom margin */
}

.nav-action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2rem;
  margin: 0;
  padding: 0;
  color: var(--pico-muted-color);
  background-color: var(--pico-card-background-color);
  border: 1px solid var(--pico-muted-border-color);
  text-decoration: none;
  transition: background-color 0.15s ease, color 0.15s ease;
}

.nav-action + .nav-action {
  margin-left: -1px; /* the two borders become one line */
}

.nav-action:first-child {
  border-radius: var(--pico-border-radius) 0 0 var(--pico-border-radius);
}

.nav-action:last-child {
  border-radius: 0 var(--pico-border-radius) var(--pico-border-radius) 0;
}

.nav-action:hover,
.nav-action:focus-visible {
  color: var(--pico-primary);
  background-color: color-mix(in srgb, var(--pico-primary) 12%, var(--pico-card-background-color));
  position: relative; /* keeps the hovered edge above its neighbour */
}

.nav-action i {
  font-size: var(--fs-md);
  line-height: 1;
}
</style>
