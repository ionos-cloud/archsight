// Symbols (Iconoir names) for the values of enumerated annotations, so a value reads at a glance:
// what a component is built as, and what an executable does.
const SYMBOLS = {
  'component/type': {
    executable: 'play',
    library: 'book-stack',
    module: 'box-3d-three-points',
    plugin: 'plug-type-a',
    frontend: 'web-window',
    other: 'code-brackets',
  },
  'component/role': {
    service: 'cloud-sync',
    cli: 'terminal',
    job: 'timer',
    operator: 'settings',
    agent: 'cpu',
  },
}

// Labels that the last key segment alone would make ambiguous (two rows called "Tags")
const LABELS = {
  'architecture/kind': 'Architecture style',
  'architecture/size': 'Architecture size',
}

// Annotations shown first in the Details table: how a resource is classified, before the rest
export const LEAD_KEYS = [
  'architecture/aliases',
  'component/type',
  'component/role',
  'architecture/kind',
  'architecture/size',
  'architecture/tags',
]

export function symbolFor(key, value) {
  return SYMBOLS[key]?.[value] || null
}

export function labelFor(key) {
  return LABELS[key] || null
}
