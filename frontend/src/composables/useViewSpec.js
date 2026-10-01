const list = (raw) => (raw || '').split(',').map(s => s.trim()).filter(Boolean)

// The query, columns and sort of a View resource from its annotations
export function viewSpec(annotations) {
  const type = annotations['view/type'] || 'list:name+kind'
  return {
    query: annotations['view/query'],
    fields: list(annotations['view/fields']),
    sort: list(annotations['view/sort']),
    showKind: type === 'list:name+kind',
  }
}
