import { ref, watch, onMounted, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { searchParams } from './useSearchScope.js'

const DEBOUNCE_MS = 300

// The query box in the top bar: shows the query of the search page (also after a reload or a back/forward step),
// searches while typing without piling up history entries, clears with one click and takes focus on "/".
export function useSearchBox(scope) {
  const router = useRouter()
  const route = useRoute()
  const query = ref('')
  let debounceTimer = null

  // The URL is the truth: follow it, but never overwrite what is being typed (the same text is a no-op)
  watch(
    () => [route.name, route.query.q],
    ([name, q]) => {
      if (name === 'search' && (q || '') !== query.value.trim()) query.value = q || ''
    },
    { immediate: true },
  )

  function go() {
    const to = { name: 'search', query: searchParams(query.value, scope.value) }
    // on the search page a new query replaces the old one, from anywhere else it is a new step
    return route.name === 'search' ? router.replace(to) : router.push(to)
  }

  function onInput() {
    clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => { if (query.value.trim()) go() }, DEBOUNCE_MS)
  }

  function onSubmit() {
    clearTimeout(debounceTimer)
    if (query.value.trim()) go()
  }

  function clear() {
    clearTimeout(debounceTimer)
    query.value = ''
    document.getElementById('search-input')?.focus()
  }

  function onKeydown(event) {
    if (event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey) return
    const target = event.target
    if (target.closest?.('input, textarea, select, [contenteditable="true"]')) return
    event.preventDefault()
    document.getElementById('search-input')?.focus()
  }

  onMounted(() => window.addEventListener('keydown', onKeydown))
  onBeforeUnmount(() => {
    window.removeEventListener('keydown', onKeydown)
    clearTimeout(debounceTimer)
  })

  return { query, onInput, onSubmit, clear }
}
