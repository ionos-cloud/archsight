import { ref } from 'vue'

// Whether the sidebar is hidden to give the content the full width. One shared state: the
// toggle in the navigation bar sets it, the layout (App.vue) applies it.
const COLLAPSED_KEY = 'archsight.sidebar.collapsed'

function storedCollapsed() {
  try {
    return localStorage.getItem(COLLAPSED_KEY) === '1'
  } catch {
    return false // storage can be blocked, the choice is then just not remembered
  }
}

const collapsed = ref(storedCollapsed())

export function toggleSidebar() {
  collapsed.value = !collapsed.value
  try {
    localStorage.setItem(COLLAPSED_KEY, collapsed.value ? '1' : '0')
  } catch {
    // not remembered, still applied
  }
}

// Narrow windows stack the sidebar above the content; there it is closed until the menu button
// opens it, and not remembered.
const mobileOpen = ref(false)

export function toggleMobileSidebar() {
  mobileOpen.value = !mobileOpen.value
}

export function useSidebarCollapsed() {
  return { collapsed, toggleSidebar, mobileOpen, toggleMobileSidebar }
}
