import { ref, watch } from 'vue'

// The sidebar's Pages / Kinds tab. One shared state: the sidebar shows it, search follows it.
const TAB_KEY = 'archsight.sidebar.tab'
export const TABS = [
  { id: 'pages', title: 'Pages', icon: 'iconoir-book' },
  { id: 'kinds', title: 'Kinds', icon: 'iconoir-folder' },
]

function storedTab() {
  try {
    const tab = localStorage.getItem(TAB_KEY)
    return TABS.some((t) => t.id === tab) ? tab : null
  } catch {
    return null // storage can be blocked, the tab is then just not remembered
  }
}

const chosenTab = ref(storedTab() || 'pages')

export function selectTab(id) {
  if (!TABS.some((t) => t.id === id)) return
  chosenTab.value = id
  try {
    localStorage.setItem(TAB_KEY, id)
  } catch {
    // not remembered, still applied
  }
}

// Which tab a route belongs to; null (home, docs, ...) has no opinion and keeps the current tab.
// A search follows its scope, so page searches (tag links included) stay on the Pages tab.
export function routeGroup(route) {
  if (route.name === 'page') return 'pages'
  if (route.name === 'search') return route.query.scope === 'pages' ? 'pages' : 'kinds'
  if (['kind', 'instance', 'editor-new', 'editor-edit'].includes(route.name)) return 'kinds'
  return null
}

// Navigating between pages and kinds switches the tab; a manual switch holds until then.
// Call once (App.vue).
export function useSidebarTabFollowsRoute(route) {
  watch(() => routeGroup(route), (group) => {
    if (group) selectTab(group)
  }, { immediate: true })
}

export function useSidebarTab() {
  return { chosenTab, selectTab, TABS }
}
