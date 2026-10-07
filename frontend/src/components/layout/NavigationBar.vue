<script setup>
import { watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useSearchScope, searchParams } from '../../composables/useSearchScope.js'
import { useSearchBox } from '../../composables/useSearchBox.js'

const router = useRouter()
const route = useRoute()
const { scope, placeholder } = useSearchScope()
const { query, onInput, onSubmit, clear } = useSearchBox(scope)

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
        <button v-if="query" type="button" class="search-clear" aria-label="Clear search" title="Clear" @click="clear">
          <i class="iconoir-xmark" aria-hidden="true"></i>
        </button>
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
  position: relative;
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.search-container input.search {
  padding-right: 2.25rem; /* room for the clear button */
}

.search-clear {
  position: absolute;
  right: 0.5rem;
  top: 50%;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  margin: 0;
  padding: 0;
  transform: translateY(-50%);
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--pico-muted-color);
  cursor: pointer;
}

.search-clear:hover,
.search-clear:focus-visible {
  background-color: var(--tint);
  color: var(--pico-color);
}

.search-container input.search {
  min-width: 700px;
}
</style>
