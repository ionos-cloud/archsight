import { computed, inject } from 'vue'
import { useSidebarTab } from './useSidebarTab.js'

// Search follows the sidebar tab: in the Pages tab it looks for pages, in the Kinds tab for everything.
const KIND_PREFIX = /^\s*[A-Za-z]\w*\s*:/ // `Page: ...`, the query language's kind filter
const BARE_WORDS = /^[\w .\-/]+$/

// What is sent to the API for what the user typed. Kinds scope is untouched. Pages scope:
// - an explicit kind prefix stays as written,
// - plain words match a page's name, title or text (regexes are case-insensitive),
// - anything else is taken as a query expression on pages.
export function scopedQuery(raw, scope) {
  const query = String(raw ?? '').trim()
  if (scope !== 'pages' || !query || KIND_PREFIX.test(query)) return query
  if (BARE_WORDS.test(query)) {
    return `Page: name =~ "${query}" | page/title =~ "${query}" | page/content =~ "${query}"`
  }
  return `Page: ${query}`
}

// Query string params for a search in a scope (no `scope` for kinds, the URLs stay as they were)
export function searchParams(q, scope) {
  return scope === 'pages' ? { q, scope: 'pages' } : { q }
}

export function useSearchScope() {
  const pages = inject('pages', null)
  const { chosenTab } = useSidebarTab()
  const scope = computed(() => (pages?.value?.length && chosenTab.value === 'pages' ? 'pages' : 'kinds'))
  const placeholder = computed(() => (
    scope.value === 'pages'
      ? 'Search pages: title, text, name or a query like page/status == "rfc"'
      : 'Query: kubernetes, activity/status == "active"'
  ))
  return { scope, placeholder }
}
