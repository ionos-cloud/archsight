<script setup>
import { ref, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useSearchScope, searchParams } from '../../composables/useSearchScope.js'

const router = useRouter()
const route = useRoute()
const { scope, placeholder } = useSearchScope()
const query = ref('')
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
</style>
