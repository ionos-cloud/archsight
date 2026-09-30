import { ref, computed } from 'vue'

// Where the editor's diagram preview sits: 'bottom', 'right', 'full' (preview only) or 'hidden'.
// Until the user picks one it follows the window: right on wide screens, below otherwise.
// One shared state, so the rich editor and the diagram field agree, and the choice is remembered.
const STORAGE_KEY = 'archsight.diagramPreview.layout'
export const LAYOUTS = ['bottom', 'right', 'full', 'hidden']
const WIDE_QUERY = '(min-width: 1400px)'

function readStored() {
  try {
    const value = localStorage.getItem(STORAGE_KEY)
    return LAYOUTS.includes(value) ? value : null
  } catch {
    return null // storage can be blocked, the layout then just is not remembered
  }
}

const chosen = ref(readStored())
const wide = ref(typeof matchMedia === 'function' ? matchMedia(WIDE_QUERY).matches : false)
if (typeof matchMedia === 'function') {
  matchMedia(WIDE_QUERY).addEventListener('change', (e) => { wide.value = e.matches })
}

const layout = computed(() => chosen.value || (wide.value ? 'right' : 'bottom'))

function setLayout(value) {
  if (!LAYOUTS.includes(value)) return
  chosen.value = value
  try {
    localStorage.setItem(STORAGE_KEY, value)
  } catch {
    // not remembered, still applied
  }
}

export function useDiagramPreviewLayout() {
  return { layout, setLayout }
}
